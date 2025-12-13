# 02. Документы-источники, Парсинг и Глобальный Контекст

## 0. Технические требования
*   **Расширение PostgreSQL:** `pgvector` - для работы с векторными эмбеддингами
    *   Устанавливается командой: `CREATE EXTENSION IF NOT EXISTS vector;`
    *   Используется для хранения эмбеддингов размерности 1536 (совместимо с OpenAI embeddings)

## 1. Загрузка и Хранение
*   **Сущность:** `SourceDocument` (type: Protocol, SAP, CSR_Prev, IB).
*   **Flow:**
    1.  User upload -> Next.js -> Supabase Storage.
    2.  Next.js триггерит Python API: `POST /api/v1/parse`.
    3.  Python качает файл из Supabase Storage (или по URL) и запускает парсер (по умолчанию Docling).
    4.  Парсинг выполняется в фоне (BackgroundTasks), секции автоматически сохраняются в таблицу `document_sections`.

### Структура таблицы `source_documents`
*   **Основные поля:**
    *   `id`, `project_id`, `name`, `storage_path`, `doc_type`, `status`, `created_at`
*   **Метаданные парсинга:**
    *   `parsing_metadata` (JSONB) - технические метрики парсинга (время обработки, количество страниц и т.д.)
    *   `detected_tables_count` (INT) - количество таблиц, обнаруженных парсером Docling
*   **Оценка качества парсинга:**
    *   `parsing_quality_score` (INT) - оценка пользователя качества парсинга (1-5)
    *   `parsing_quality_comment` (TEXT) - комментарий пользователя к ошибкам парсинга

## 2. Архитектура Парсеров (Python)
Система использует паттерн Strategy для поддержки различных парсеров:

*   **Базовый класс:** `BaseParser` (абстрактный) в `ai_engine/services/base_parser.py`
    *   Метод: `async parse(file_path: str) -> List[Section]`
*   **Реализации:**
    *   `DoclingParser` - парсинг через Docling (PDF/DOCX -> Markdown)
    *   `AzureParser` - (планируется) парсинг через Azure Document Intelligence
*   **Переключение парсера:** Замена одной строки в `main.py`:
    ```python
    parser = DoclingParser()  # или AzureParser()
    ```

## 3. Structural Parsing Pipeline (Python)
Вместо простой нарезки, мы восстанавливаем иерархию:
1.  **Format Conversion:** PDF/DOCX -> Markdown (с сохранением таблиц).
    *   Реализовано в `DoclingParser` через `DocumentConverter`
2.  **Segmentation:** Разбиение Markdown по заголовкам (H1, H2, H3, ...).
    *   Автоматическое извлечение номеров секций (например, "3.1.2" из заголовка)
    *   Определение уровня вложенности по уровню заголовка
3.  **Storage:** Запись в таблицу `document_sections`:
    *   `section_number`: "3.1" (извлечен из заголовка)
    *   `header`: "3.1 Study Design"
    *   `content_markdown`: Текст + Таблицы в MD формате.
    *   `content_text`: Чистый текст без разметки (для поиска)
    *   `embedding`: Векторное представление секции (vector(1536)) для семантического поиска
    *   `canonical_code`: Ссылка на каноническую секцию из справочника (FK к `canonical_sections`)
    *   `classification_confidence`: Уверенность автоматической классификации (0.0-1.0)

### Структура таблицы `document_sections`
*   **Основные поля:**
    *   `id`, `document_id`, `section_number`, `header`, `page_number`, `created_at`
*   **Контент:**
    *   `content_text` (TEXT) - чистый текст для поиска
    *   `content_markdown` (TEXT) - текст с разметкой таблиц (для LLM)
*   **Векторное представление:**
    *   `embedding` (vector(1536)) - эмбеддинг секции для гибридного поиска
*   **Классификация:**
    *   `canonical_code` (TEXT, FK) - ссылка на каноническую секцию из справочника
    *   `classification_confidence` (FLOAT) - уверенность автоматической классификации (0.0-1.0)

## 4. Global Context Injection (Паспорт Исследования)
Механизм "понимания всего документа".

### Структура таблицы `study_globals`
*   `id` (UUID, PK) - уникальный идентификатор
*   `project_id` (UUID, FK) - ссылка на проект
*   `variable_name` (TEXT) - название переменной (например, "Phase", "Drug_Name")
*   `variable_value` (TEXT) - значение переменной
*   `source_section_id` (UUID, FK) - ссылка на секцию документа, из которой извлечена переменная
*   `created_at` (TIMESTAMPTZ) - время создания

**Extraction Process:**
1.  После парсинга Протокола, AI находит раздел "Synopsis".
2.  LLM извлекает ключевые факты: Phase, Drug Name, Primary Endpoint, Study Population, Blinding и т.д.
3.  Сохраняет в `study_globals` с указанием `source_section_id` для отслеживания источника.

**Использование:** Эти данные приклеиваются к системному промпту при любой генерации.

## 5. Таксономия секций (Справочники)

Система использует справочники для стандартизации классификации секций документов:

### Таблица `canonical_sections`
Справочник канонических секций документов:
*   `code` (TEXT, PK) - уникальный код секции (например, "INCLUSION_CRITERIA", "EXCLUSION_CRITERIA")
*   `name` (TEXT) - название секции
*   `description` (TEXT) - описание секции

### Таблица `canonical_anchors`
Справочник якорей для классификации секций:
*   `id` (UUID, PK) - уникальный идентификатор
*   `canonical_code` (TEXT, FK) - ссылка на каноническую секцию
*   `anchor_text` (TEXT) - текст-якорь для сопоставления с секциями документов
*   `embedding` (vector(1536)) - векторное представление якоря для семантического поиска

**Использование:** При парсинге документа система может автоматически классифицировать секции, сопоставляя их с каноническими секциями через якоря.

## 6. Hybrid Search (Страховка)
*   Для каждой секции в `document_sections` генерируется эмбеддинг.
*   Используется для поиска информации, которая не попала в жесткий маппинг (сноски, приложения).
*   Используется расширение PostgreSQL `pgvector` для работы с векторными данными.
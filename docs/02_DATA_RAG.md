# 02. Документы-источники, Парсинг и Глобальный Контекст

## 0. Технические требования

*   **Расширение PostgreSQL:** `pgvector` - для работы с векторными эмбеддингами
    *   Устанавливается командой: `CREATE EXTENSION IF NOT EXISTS vector;`
    *   Используется для хранения эмбеддингов размерности 1536 (совместимо с OpenAI embeddings)
    *   Используется для гибридного поиска секций документов через cosine similarity

## 1. Загрузка и Хранение исходных документов

### 1.1 Сущность SourceDocument

**Типы документов:** Protocol, SAP (Statistical Analysis Plan), CSR_Prev (Previous CSR), IB (Investigator Brochure)

**Статусы документов:**
- `uploading` - документ загружается
- `processing` - документ обрабатывается парсером
- `indexed` - документ успешно обработан и секции сохранены в БД
- `error` - произошла ошибка при обработке

### 1.2 Процесс загрузки документа

**Flow загрузки:**

1. **Пользователь загружает документ** через компонент `UploadSourceModal`:
   - Выбирает тип документа (Protocol, SAP, CSR_Prev, IB)
   - Опционально выбирает шаблон для классификации секций (`custom_template_id`)
   - Загружает PDF файл (drag-and-drop или выбор файла)
   - Максимальный размер файла: 50MB

2. **Next.js Server Action `uploadSourceAction`** (`app/projects/[id]/actions.ts`):
   - Проверяет аутентификацию пользователя
   - Проверяет доступ к проекту через RPC функцию `has_project_access`
   - Валидирует файл (только PDF, максимум 50MB)
   - Загружает файл в Supabase Storage:
     - Bucket: `documents`
     - Путь: `projects/{projectId}/sources/{timestamp}-{random}.pdf`
   - Создает запись в `source_documents` через RPC функцию `create_source_document`:
     - Обходит проблемы с RLS (Row Level Security)
     - Устанавливает начальный статус `uploading`
   - Вызывает Python API: `POST /api/v1/parse` с параметрами:
     ```json
     {
       "document_id": "uuid-документа",
       "file_path": "projects/{projectId}/sources/{fileName}",
       "file_url": "https://...",  // public URL файла
       "template_id": "uuid-шаблона"  // опционально
     }
     ```

3. **Python AI Engine** (`ai_engine/services/parser.py`):
   - Получает запрос на парсинг через эндпоинт `POST /api/v1/parse`
   - Запускает обработку в фоне (BackgroundTasks)
   - Скачивает файл из Supabase Storage или по URL
   - Парсит документ через `DoclingParser`
   - Классифицирует секции (если указан `template_id`)
   - Создает эмбеддинги для секций
   - Сохраняет секции в таблицу `source_sections`
   - Обновляет статус документа на `indexed` или `error`

### 1.3 Структура таблицы `source_documents`

**Основные поля:**
- `id` (UUID, PK) - уникальный идентификатор
- `project_id` (UUID, FK → projects) - ссылка на проект
- `name` (TEXT) - имя файла
- `storage_path` (TEXT) - путь в Supabase Storage (устаревшее, использовать `file_path`)
- `file_path` (TEXT) - путь к файлу в Storage (может быть NULL для `manual_entry`)
- `input_type` (ENUM: `file`, `manual_entry`) - тип входных данных
- `doc_type` (TEXT) - тип документа (Protocol, SAP, CSR_Prev, IB)
- `status` (TEXT) - статус обработки (`uploading`, `processing`, `indexed`, `error`)
- `created_at` (TIMESTAMPTZ) - время создания

**Версионирование документов:**
- `parent_document_id` (UUID, FK → source_documents) - ссылка на родительский документ для версионирования
- `version_label` (TEXT) - метка версии (например, "v1.0", "v2.1")
- `is_current_version` (BOOLEAN, default: true) - **критически важно:** при генерации секций используются только документы с `is_current_version = TRUE`

**Метаданные парсинга:**
- `parsing_metadata` (JSONB) - технические метрики парсинга:
  ```json
  {
    "parsing_time_seconds": 45.2,
    "page_count": 120,
    "sections_count": 35,
    "parsed_at": "2024-01-15T10:30:00Z"
  }
  ```
- `detected_tables_count` (INT) - количество таблиц, обнаруженных парсером Docling

**Оценка качества парсинга (пользовательская):**
- `parsing_quality_score` (INT) - оценка пользователя качества парсинга (1-5)
- `parsing_quality_comment` (TEXT) - комментарий пользователя к ошибкам парсинга

**Классификация:**
- `template_id` (UUID, FK → custom_templates) - пользовательский шаблон для классификации документа (опционально, может быть указан при загрузке)

## 2. Архитектура Парсеров (Python)

### 2.1 Паттерн Strategy

Система использует паттерн Strategy для поддержки различных парсеров документов.

**Базовый класс:** `BaseParser` (абстрактный) в `ai_engine/services/base_parser.py`
- Метод: `async parse(file_path: str) -> List[Section]`
- Определяет интерфейс для всех парсеров

**Реализации:**
- `DoclingParser` - парсинг через Docling (PDF/DOCX -> Markdown)
  - Конвертирует PDF/DOCX в Markdown с сохранением структуры
  - Извлекает таблицы в формате Markdown
  - Сохраняет иерархию заголовков
- `AzureParser` - (планируется) парсинг через Azure Document Intelligence

**Переключение парсера:** Замена одной строки в `main.py`:
```python
parser = DoclingParser()  # или AzureParser()
```

### 2.2 Structural Parsing Pipeline

Вместо простой нарезки текста, система восстанавливает иерархию документа:

1. **Format Conversion:** PDF/DOCX -> Markdown (с сохранением таблиц)
   - Реализовано в `DoclingParser` через `DocumentConverter`
   - Сохраняет структуру документа (заголовки, параграфы, таблицы)

2. **Segmentation:** Разбиение Markdown по заголовкам (H1, H2, H3, ...)
   - Автоматическое извлечение номеров секций (например, "3.1.2" из заголовка)
   - Определение уровня вложенности по уровню заголовка
   - Сохранение контекста (номер страницы, координаты текста)

3. **Storage:** Запись в таблицу `source_sections`:
   - `section_number`: "3.1" (извлечен из заголовка)
   - `header`: "3.1 Study Design"
   - `content_markdown`: Текст + Таблицы в MD формате (для LLM)
   - `content_text`: Чистый текст без разметки (для поиска)
   - `page_number`: Номер страницы в исходном документе
   - `embedding`: Векторное представление секции (vector(1536)) для семантического поиска
   - `custom_section_id`: Ссылка на секцию пользовательского шаблона (FK к `custom_sections`)
   - `classification_confidence`: Уверенность автоматической классификации (0.0-1.0)
   - `bbox`: Координаты текста в формате JSONB для подсветки в PDF

### 2.3 Структура таблицы `source_sections`

**Основные поля:**
- `id` (UUID, PK) - уникальный идентификатор
- `document_id` (UUID, FK → source_documents) - ссылка на документ
- `section_number` (TEXT) - номер секции (например, "3.1.2")
- `header` (TEXT) - заголовок секции
- `page_number` (INT) - номер страницы в исходном документе
- `created_at` (TIMESTAMPTZ) - время создания

**Контент:**
- `content_text` (TEXT) - чистый текст для поиска (без разметки)
- `content_markdown` (TEXT) - текст с разметкой таблиц (для LLM)

**Векторное представление:**
- `embedding` (vector(1536)) - эмбеддинг секции для гибридного поиска
  - Создается из заголовка + первые 500 символов контента
  - Используется для семантического поиска через cosine similarity

**Классификация:**
- `custom_section_id` (UUID, FK → custom_sections) - ссылка на секцию пользовательского шаблона
  - Устанавливается автоматически при парсинге, если указан `template_id`
  - Используется векторный поиск для привязки секций к шаблону
- `classification_confidence` (FLOAT) - уверенность автоматической классификации (0.0-1.0)

**Координаты:**
- `bbox` (JSONB) - координаты текста в формате:
  ```json
  {
    "page": 1,
    "x": 100,
    "y": 200,
    "w": 300,
    "h": 50
  }
  ```
  Используется для подсветки текста в PDF при просмотре

## 3. Классификация секций документов

### 3.1 Процесс классификации

При парсинге документа с указанным `template_id` (custom_template_id):

1. **Для каждой секции документа:**
   - Создается эмбеддинг заголовка секции через LLM
   - Выполняется векторный поиск ближайшей секции в пользовательском шаблоне

2. **Векторный поиск** (`ai_engine/services/classifier.py`):
   - Ищет в `custom_sections` с `custom_template_id = template_id`
   - Использует эмбеддинги из связанных `ideal_sections` (через `custom_section.ideal_section_id`)
   - Вычисляет cosine similarity между эмбеддингом заголовка и эмбеддингами секций шаблона
   - Порог similarity: **0.85** (настраивается в `SectionClassifier.similarity_threshold`)

3. **Результат:**
   - Если similarity >= 0.85, секция привязывается к шаблону через `custom_section_id`
   - Если similarity < 0.85, секция остается без классификации (`custom_section_id = NULL`)

### 3.2 Класс SectionClassifier

**Метод:** `classify_section(session, header_text, template_id) -> Optional[UUID]`

**Алгоритм:**
1. Получает эмбеддинг для заголовка секции через `LLMClient.get_embedding()`
2. Выполняет SQL запрос с cosine similarity:
   ```sql
   SELECT custom_sections.id, 
          (1 - cosine_distance(ideal_sections.embedding, :header_embedding)) as similarity
   FROM custom_sections
   JOIN ideal_sections ON custom_sections.ideal_section_id = ideal_sections.id
   WHERE custom_sections.custom_template_id = :template_id
     AND ideal_sections.embedding IS NOT NULL
   ORDER BY cosine_distance(ideal_sections.embedding, :header_embedding)
   LIMIT 1
   ```
3. Если similarity >= 0.85, возвращает `custom_section_id`, иначе `None`

## 4. Global Context Injection (Паспорт Исследования)

### 4.1 Механизм "понимания всего документа"

Глобальные переменные исследования (Study Globals) - это "паспорт исследования", который содержит ключевые факты:
- Phase (фаза исследования)
- Drug Name (название препарата)
- Primary Endpoint (первичная конечная точка)
- Study Population (популяция исследования)
- Blinding (ослепление)
- Inclusion/Exclusion Criteria (критерии включения/исключения)
- И другие метаданные

Эти данные автоматически приклеиваются к системному промпту при любой генерации секций документов.

### 4.2 Структура таблицы `study_globals`

- `id` (UUID, PK) - уникальный идентификатор
- `project_id` (UUID, FK → projects) - ссылка на проект
- `variable_name` (TEXT) - название переменной (например, "Phase", "Drug_Name", "Primary_Endpoint")
- `variable_value` (TEXT) - значение переменной
- `source_section_id` (UUID, FK → source_sections) - ссылка на секцию документа, из которой извлечена переменная (для отслеживания источника)
- `created_at` (TIMESTAMPTZ) - время создания

### 4.3 Процесс извлечения глобальных переменных

**Класс:** `GlobalExtractor` (`ai_engine/services/extractor.py`)

**Метод:** `extract_globals(session, project_id) -> Dict[str, str]`

**Алгоритм:**

1. **Поиск секций с Synopsis:**
   - Ищет секции документов проекта с заголовком, содержащим "synopsis" (case-insensitive)
   - Фильтрует только актуальные версии (`is_current_version = TRUE`)
   - Ограничивает поиск 5 секциями

2. **Fallback:**
   - Если секции с Synopsis не найдены, берет первые 5 секций документов проекта (по `section_number`)

3. **Извлечение через LLM:**
   - Собирает текст из найденных секций (заголовок + контент)
   - Формирует промпт для LLM:
     ```
     System: Ты - эксперт по медицинским исследованиям. 
     Извлеки структурированные данные из текста протокола исследования.
     Верни результат в формате JSON с ключами: Phase, Drug_Name, Population, 
     Primary_Endpoint, Secondary_Endpoints, Study_Design, Inclusion_Criteria, Exclusion_Criteria.
     ```
   - Вызывает LLM с `temperature=0.3` (для более детерминированного результата)

4. **Сохранение в БД:**
   - Парсит JSON из ответа LLM
   - Удаляет старые записи проекта из `study_globals`
   - Создает новые записи для каждой переменной
   - Сохраняет `source_section_id` для отслеживания источника

**Использование:**
- Глобальные переменные автоматически добавляются в системный промпт при генерации секций через `Writer.generate_section()`
- Формат в промпте: Bullet-points (например, "- **Phase**: Phase III")

## 5. Hybrid Search (Страховка)

### 5.1 Назначение

Гибридный поиск используется как "страховка" для поиска информации, которая не попала в жесткий маппинг через Template Graph:
- Сноски
- Приложения
- Дополнительные разделы, не привязанные к шаблону

### 5.2 Механизм работы

1. **Создание эмбеддингов:**
   - Для каждой секции в `source_sections` создается эмбеддинг при парсинге
   - Эмбеддинг создается из заголовка + первые 500 символов контента
   - Размерность: 1536 (совместимо с OpenAI embeddings)

2. **Векторный поиск:**
   - Используется расширение PostgreSQL `pgvector`
   - Поиск через cosine similarity: `1 - cosine_distance(embedding1, embedding2)`
   - Порог similarity: 0.85 (настраивается)

3. **Использование:**
   - При генерации секций, если жесткий маппинг не нашел исходные данные
   - Можно выполнить векторный поиск по всем секциям проекта
   - Найти наиболее релевантные секции по семантическому сходству

### 5.3 Пример использования

```python
# Поиск релевантных секций через векторный поиск
from sqlalchemy import select
from pgvector.sqlalchemy import Vector
from sqlalchemy.sql import func

query = (
    select(SourceSection)
    .where(
        SourceDocument.project_id == project_id,
        SourceDocument.is_current_version == True
    )
    .order_by(
        func.cosine_distance(SourceSection.embedding, query_embedding)
    )
    .limit(5)
)
```

## 6. Обработка ошибок

### 6.1 Ошибки при загрузке

- **Неверный тип файла:** Только PDF файлы поддерживаются
- **Превышен размер:** Максимальный размер файла 50MB
- **Ошибка доступа:** Пользователь должен быть участником проекта (`project_members`)
- **Ошибка RLS:** Используется RPC функция `create_source_document` для обхода проблем с RLS

### 6.2 Ошибки при парсинге

- **Ошибка скачивания файла:** Статус документа обновляется на `error`, метаданные содержат описание ошибки
- **Ошибка парсинга:** Статус документа обновляется на `error`, `parsing_metadata` содержит описание ошибки
- **Ошибка классификации:** Секции сохраняются без `custom_section_id` (можно классифицировать вручную позже)
- **Ошибка создания эмбеддинга:** Секция сохраняется без эмбеддинга (гибридный поиск не будет работать для этой секции)

### 6.3 Логирование

Все ошибки логируются в консоль Python сервиса для диагностики:
- Ошибки скачивания файлов
- Ошибки парсинга
- Ошибки создания эмбеддингов
- Ошибки классификации секций
- Ошибки извлечения глобальных переменных

## 7. Версионирование документов

### 7.1 Механизм версионирования

Документы поддерживают версионирование через поля:
- `parent_document_id` - ссылка на родительский документ
- `version_label` - метка версии (например, "v1.0", "v2.1")
- `is_current_version` - флаг актуальной версии

### 7.2 Использование при генерации

**Критически важно:** При генерации секций через `Writer.generate_section()` используются только документы с `is_current_version = TRUE`.

Это гарантирует, что:
- Генерация всегда использует актуальные версии документов
- Старые версии не влияют на генерацию новых секций
- Можно отслеживать историю изменений документов

### 7.3 Процесс создания новой версии

1. Пользователь загружает новый файл с тем же типом документа
2. Создается новая запись в `source_documents`:
   - `parent_document_id` указывает на предыдущую версию
   - `version_label` устанавливается вручную или автоматически
   - `is_current_version = TRUE` для новой версии
3. Старая версия обновляется: `is_current_version = FALSE`
4. Новая версия парсится и секции сохраняются в `source_sections`
5. При следующей генерации будут использоваться секции из новой версии

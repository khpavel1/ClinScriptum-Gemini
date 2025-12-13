# 04. AI Engine: Logic & Generation

## 1. Архитектура Сервиса (Python)
*   **Framework:** FastAPI.
*   **Libs:** Docling (parsing), SQLAlchemy (DB), YandexGPT SDK / OpenAI-compatible client.
*   **Logic:** Deterministic Mapping + LLM Transformation.

### 1.1 Структура Парсеров
*   **Модуль:** `ai_engine/services/`
*   **Базовый класс:** `BaseParser` (абстрактный)
    *   Определяет интерфейс: `async parse(file_path: str) -> List[Section]`
*   **Реализации:**
    *   `DoclingParser(BaseParser)` - парсинг через Docling
        *   Конвертирует PDF/DOCX в Markdown
        *   Разбивает на секции по заголовкам
        *   Извлекает номера секций и уровни иерархии
    *   `AzureParser(BaseParser)` - (планируется) для Azure Document Intelligence
*   **Использование в API:**
    *   Эндпоинт: `POST /parse`
    *   Инициализация парсера в `main.py` (легко заменить на другой)

### 1.2 API Эндпоинты

#### Эндпоинт `POST /parse` (синхронный)
Парсит документ и возвращает список секций без сохранения в БД.

**Запрос:**
```json
POST /parse
{
  "file_path": "/path/to/document.pdf"
}
```

**Ответ:**
```json
{
  "sections": [
    {
      "section_number": "3.1",
      "header": "3.1 Study Design",
      "content_text": "Чистый текст без разметки...",
      "content_markdown": "Текст с **разметкой** и таблицами...",
      "page_number": null,
      "hierarchy_level": 2
    }
  ],
  "total_sections": 15
}
```

#### Эндпоинт `POST /api/v1/parse` (асинхронный с сохранением в БД)
Запускает парсинг документа в фоне и сохраняет секции в таблицу `document_sections`.

**Запрос:**
```json
POST /api/v1/parse
{
  "document_id": "uuid-документа",
  "file_path": "путь/в/supabase/storage/document.pdf",
  "file_url": "https://example.com/document.pdf"  // опционально, если файл доступен по URL
}
```

**Ответ:**
```json
{
  "message": "Парсинг документа запущен в фоне",
  "document_id": "uuid-документа",
  "status": "processing"
}
```

**Особенности:**
*   Парсинг выполняется асинхронно в фоне (BackgroundTasks)
*   Файл скачивается из Supabase Storage (по `file_path`) или по URL (если указан `file_url`)
*   Секции автоматически сохраняются в таблицу `document_sections` с привязкой к `document_id`
*   Таблицы сохраняются в формате Markdown в поле `content_markdown`

**Обработка ошибок:**
*   `400` - Не указан `file_path` или `file_url`, или некорректный формат запроса
*   `404` - Файл не найден
*   `500` - Внутренняя ошибка при запуске парсинга

### 1.3 Сервис Парсинга (`services/parser.py`)
Модуль `process_document` обеспечивает полный цикл обработки документа:

1. **Скачивание файла:**
   *   Из Supabase Storage (если указан `file_path`)
   *   По HTTP/HTTPS URL (если указан `file_url`)
2. **Парсинг:** Использует `DoclingParser` для конвертации в Markdown и разбиения на секции
3. **Сохранение в БД:** Автоматически сохраняет все секции в таблицу `document_sections` через SQLAlchemy сессию

## 2. Логика Генерации (The "Brain")
При запросе "Сгенерируй раздел 9.1 CSR":

1.  **Context Assembly (Сборка контекста):**
    *   **Layer 1 (Global):** Загрузить JSON из `study_globals` (Паспорт).
    *   **Layer 2 (Narrative):** Загрузить текст Синопсиса.
    *   **Layer 3 (Deterministic):** Найти нужные секции Протокола по правилам маппинга (например, Protocol Section 3.1).
    *   **Layer 4 (Vector fallback):** (Опционально) Найти похожие куски вектором, если детерминированный поиск вернул пустоту.

2.  **Prompt Engineering:**
    ```text
    [SYSTEM]
    Роль: Мед. писатель.
    Глобальные данные: {Global JSON}
    Контекст Синопсиса: {Synopsis Text}

    [SOURCE DATA]
    Текст секции: {Protocol Markdown}
    Таблицы: {Tables Markdown}

    [INSTRUCTION]
    Задача: Напиши раздел CSR.
    Правила:
    1. Глаголы в прошедшее время (was performed, were randomized).
    2. Таблицы переведи в текстовое описание (статистический вывод).
    3. Не выдумывай цифры, которых нет в источнике.
    ```

3.  **Generation:** Отправка в YandexGPT Pro / Qwen.

## 3. Traceability
*   В ответе API возвращает не только текст, но и `used_source_ids` (какие секции протокола использовались).
*   Это сохраняется в метаданные версии секции для аудита.
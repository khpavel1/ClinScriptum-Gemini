# 04. AI Engine: Logic & Generation

## 1. Архитектура Сервиса (Python)
*   **Framework:** FastAPI.
*   **Task Queue:** Celery с Redis в качестве broker и backend.
*   **Libs:** Docling (parsing), SQLAlchemy (Async) + asyncpg, pgvector (vector search), YandexGPT SDK / OpenAI-compatible client.
*   **Logic:** Structure-RAG с поддержкой Template Graph (Граф Шаблонов).
*   **Архитектура:** Микросервис с Dependency Injection для БД и асинхронной обработкой задач через Celery.

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

### 1.2 Модели Базы Данных (SQLAlchemy)

Все модели определены в `ai_engine/models.py`:

*   **DocTemplate** - типы документов (шаблоны)
*   **TemplateSection** - узлы графа шаблонов (структура секций, "Золотой стандарт")
*   **SectionMapping** - ребра графа (правила переноса между секциями)
*   **SourceDocument** - метаданные исходных документов
*   **SourceSection** - секции исходных документов (Inputs) с привязкой к шаблонам
*   **StudyGlobal** - глобальные переменные исследования (Паспорт)
*   **Deliverable** - готовые документы (Outputs/Deliverables), созданные на основе шаблонов
*   **DeliverableSection** - секции готовых документов (Outputs) с контентом для редактора

Все модели используют `mapped_column` и `pgvector.sqlalchemy.Vector` для векторных полей.

### 1.3 API Эндпоинты

#### Эндпоинт `POST /parse` (асинхронный с сохранением в БД)
Запускает парсинг документа в фоне с классификацией секций по шаблону.

**Запрос:**
```json
POST /parse
{
  "document_id": "uuid-документа",
  "file_path": "путь/в/supabase/storage/document.pdf",
  "file_url": "https://example.com/document.pdf",  // опционально
  "template_id": "uuid-шаблона"  // опционально, для классификации секций
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
*   Парсинг выполняется асинхронно через Celery очередь (Redis broker)
*   Автоматическая классификация секций через векторный поиск (если указан `template_id`)
*   Создание эмбеддингов для секций (для гибридного поиска)
*   Сохранение метаданных парсинга (время, количество страниц) в `source_documents.parsing_metadata`
*   Автоматические повторные попытки при ошибках (до 3 раз с задержкой 60 секунд)

#### Эндпоинт `POST /generate`
Генерирует целевую секцию документа на основе Template Graph и сохраняет результат в таблицу `deliverable_sections`.

**Запрос:**
```json
POST /generate
{
  "project_id": "uuid-проекта",
  "target_section_id": "uuid-целевой-секции-шаблона",
  "deliverable_id": "uuid-документа-deliverable"
}
```

**Ответ:**
```json
{
  "content": "# Название секции\n\nСгенерированный текст в формате Markdown...",
  "target_section_id": "uuid-целевой-секции-шаблона"
}
```

**Логика работы:**
1. Находит правила (`section_mappings`) для целевой секции
2. Находит исходные секции документов проекта в таблице `source_sections`
3. Собирает контекст (глобальные переменные + исходные секции)
4. Генерирует текст через LLM с учетом инструкций трансформации
5. Сохраняет результат в таблицу `deliverable_sections`:
   - Записывает сгенерированный текст в поле `content_html`
   - Обновляет статус секции на `generated`
   - Сохраняет ID использованных исходных секций в `used_source_section_ids`

#### Эндпоинт `GET /api/v1/export/{deliverable_id}`
Экспортирует deliverable в формат DOCX используя Pandoc и возвращает файл как поток.

**Параметры:**
*   `deliverable_id` (UUID, path parameter) - UUID документа для экспорта
*   `reference_docx` (string, query parameter, опционально) - Путь к шаблону DOCX с корпоративными стилями

**Ответ:**
*   `StreamingResponse` с DOCX файлом
*   Content-Type: `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
*   Content-Disposition: `attachment; filename="{название_документа}.docx"`

**Пример использования:**
```bash
# Экспорт без шаблона
GET /api/v1/export/123e4567-e89b-12d3-a456-426614174000

# Экспорт с корпоративным шаблоном
GET /api/v1/export/123e4567-e89b-12d3-a456-426614174000?reference_docx=/path/to/template.docx
```

**Обработка ошибок:**
*   `404` - Deliverable не найден или нет секций для экспорта
*   `500` - Ошибка при конвертации через Pandoc или неожиданная ошибка

**Особенности:**
*   Все секции документа объединяются в правильном порядке (по `order_index`)
*   Поддерживается применение корпоративных стилей через `reference.docx`
*   Временные файлы автоматически очищаются после генерации

### 1.4 Сервисы

#### Сервис Парсинга (`services/parser.py`)
Модуль `process_document` обеспечивает полный цикл обработки документа:

1. **Скачивание файла:**
   *   Из Supabase Storage (если указан `file_path`)
   *   По HTTP/HTTPS URL (если указан `file_url`)
2. **Парсинг:** Использует `DoclingParser` для конвертации в Markdown и разбиения на секции
3. **Классификация секций:** Автоматически привязывает секции к шаблону через векторный поиск (если указан `template_id`)
4. **Создание эмбеддингов:** Генерирует векторные представления для гибридного поиска
5. **Сохранение в БД:** Сохраняет секции в таблицу `source_sections` с метаданными парсинга

#### Очередь Задач (Celery)
Обработка документов выполняется через Celery для обеспечения надежности и масштабируемости:

*   **Broker:** Redis (для очереди задач)
*   **Backend:** Redis (для хранения результатов)
*   **Worker:** Отдельный процесс для выполнения задач парсинга
*   **Задача:** `process_document_task` в модуле `tasks.py`
*   **Особенности:**
    *   Автоматические повторные попытки при ошибках (до 3 раз)
    *   Ограничение времени выполнения задачи (30 минут максимум)
    *   Создание новой async сессии БД для каждой задачи
    *   Использование `asgiref.sync.async_to_sync` для выполнения async функций в синхронном контексте Celery

#### Сервис LLM (`services/llm.py`)
Класс `LLMClient` предоставляет методы:
*   `get_embedding(text: str) -> List[float]` - получение эмбеддинга (1536 размерности)
*   `generate_text(system_prompt, user_prompt) -> str` - генерация текста через LLM

Поддерживает YandexGPT и OpenAI-compatible API.

#### Сервис Классификации (`services/classifier.py`)
Класс `SectionClassifier` классифицирует секции документов:
*   `classify_section(header_text, template_id) -> UUID | None` - привязывает заголовок к секции шаблона через векторный поиск (cosine similarity > 0.85)

#### Сервис Экстрактора (`services/extractor.py`)
Класс `GlobalExtractor` извлекает глобальные переменные исследования:
*   `extract_globals(project_id) -> Dict[str, str]` - извлекает Phase, Drug Name, Population и т.д. из секций протокола через LLM

#### Сервис Экспорта (`services/exporter.py`)
Класс `Exporter` предоставляет функции для экспорта готовых документов (deliverables) в различные форматы:
*   `export_deliverable_to_docx(deliverable_id, db, reference_docx=None) -> bytes` - экспортирует deliverable в формат DOCX используя Pandoc
*   `export_deliverable_to_docx_file(deliverable_id, db, output_path, reference_docx=None) -> str` - экспортирует deliverable в DOCX файл на диске
*   Процесс работы:
    1. Получает все `DeliverableSections` для документа, отсортированные по `order_index`
    2. Объединяет их `content_html` в один большой HTML документ
    3. Конвертирует HTML в DOCX используя `pypandoc.convert_text`
    4. Опционально применяет корпоративный шаблон (`reference.docx`) через параметр `--reference-doc` в Pandoc
    5. Возвращает бинарные данные DOCX файла
*   Использует Pandoc для высококачественной конвертации HTML в DOCX с поддержкой корпоративных стилей

#### Сервис Генератора (`services/writer.py`)

В модуле `writer.py` определены три основных класса для генерации секций документов:

**Класс `Writer`** - основной сервис генерации секций на основе Template Graph:
*   `generate_section(session, deliverable_section_id, changed_by_user_id) -> str` - генерирует секцию для существующей `deliverable_section`
*   Процесс работы:
    1. **Context Resolution:** Находит правила маппинга (custom_mappings или ideal_mappings) для custom_section:
       - Сначала проверяет `custom_mappings` где `target_custom_section_id = custom_section.id`
       - Если нет, идет по ссылке `ideal_section_id` и ищет в `ideal_mappings`
    2. **Data Retrieval:** Находит исходные секции документов с фильтром `is_current_version = TRUE`:
       - Фильтрует только актуальные версии документов
       - Для каждого маппинга находит секции с соответствующим `custom_section_id`
       - Обрабатывает `manual_entry` так же, как обычные файлы
    3. **Global Context:** Собирает глобальные переменные из `study_globals` (Паспорт исследования)
    4. **Generation:** Формирует промпты (System + User), вызывает LLM, преобразует Markdown в HTML
    5. **Update & History:** Обновляет `deliverable_sections` и создает запись истории
*   Сохраняет результат в таблицу `deliverable_sections`:
    - Записывает сгенерированный текст в поле `content_html` (преобразует Markdown в HTML)
    - Обновляет статус секции на `draft_ai`
    - Сохраняет ID использованных исходных секций в `used_source_section_ids`
    - Создает запись в `deliverable_section_history` с причиной "AI generation"
*   Возвращает сгенерированный текст секции в формате HTML

**Примечание:** Класс `SectionWriter` удален из кода - используйте класс `Writer` вместо него. `SectionWriter` использовал устаревшие таблицы `template_sections` и `section_mappings`.

**Класс `ContentWriter`** - сервис генерации контента на основе Template Graph и глобального контекста (рекомендуется для новых интеграций):
*   `generate_section_draft(project_id, target_custom_section_id, session) -> GenerationResult` - генерирует черновик раздела (например, для CSR) на основе данных из Протокола
*   Работает с новой архитектурой шаблонов (custom_templates, custom_sections, custom_mappings)
*   Использует фильтр `is_current_version = TRUE` для выбора актуальных версий документов
*   Возвращает структурированный результат с метаданными для Audit Trail
*   Более строгая обработка ошибок и валидация данных

**Модель `GenerationResult`** (Pydantic) - результат генерации секции:
*   `content: str` - сгенерированный текст секции в формате Markdown
*   `used_source_section_ids: List[UUID]` - список UUID исходных секций, использованных для генерации
*   `mapping_logic_used: str` - описание правила маппинга, которое было применено

**Алгоритм работы `Writer.generate_section`:**
1. **Context Resolution** - находит правила маппинга:
   - Сначала проверяет `custom_mappings` где `target_custom_section_id = custom_section.id`
   - Если нет, идет по ссылке `ideal_section_id` и ищет в `ideal_mappings`
   - Правила сортируются по `order_index`
2. **Data Retrieval** - находит исходные секции документов:
   - Фильтрует только актуальные версии (`is_current_version = TRUE`) - **критически важно**
   - Для каждого маппинга находит секции с соответствующим `custom_section_id`
   - Если маппинг ссылается на `source_ideal_section_id`, находит все `custom_sections` с таким `ideal_section_id`
   - Обрабатывает `manual_entry` так же, как обычные файлы (берет текст из секции)
   - Использует `content_markdown`, если доступен, иначе `content_text`
3. **Global Context** - собирает глобальные переменные из `study_globals` (Паспорт исследования) и преобразует в строку формата Bullet-points
4. **Generation** - формирует промпты:
   - **System Message:** Роль медицинского писателя + глобальные данные исследования (строго соблюдать факты)
   - **User Message:** Исходные данные из Протокола/SAP (заголовок + контент) + инструкции трансформации из маппингов
   - Вызывает LLM с параметрами: `temperature=0.7`, `max_tokens=3000`
5. **Update & History** - обновляет `deliverable_sections` и создает запись истории:
   - Преобразует Markdown в HTML (базовое преобразование)
   - Обновляет `content_html`, `status = 'draft_ai'`, `used_source_section_ids`
   - Создает запись в `deliverable_section_history` с `change_reason = "AI generation"`

## 2. Template Graph Architecture (Граф Шаблонов)

Система использует архитектуру Template Graph для структурированной генерации документов:

### 2.1 Компоненты Графа

Система использует двухуровневую архитектуру шаблонов:

1. **Идеальные шаблоны (Ideal Templates)** - золотые стандарты структур:
   *   `ideal_templates` - идеальные шаблоны с версионированием
   *   `ideal_sections` - секции идеальных шаблонов
   *   `ideal_mappings` - правила переноса данных между идеальными секциями
   *   Имеют векторные представления (`embedding`) для семантического поиска

2. **Пользовательские шаблоны (Custom Templates)** - настройки на основе идеальных:
   *   `custom_templates` - пользовательские шаблоны (могут быть глобальными для организации или специфичными для проекта)
   *   `custom_sections` - секции пользовательских шаблонов (связь с `ideal_section_id`)
   *   `custom_mappings` - правила переноса данных для пользовательских шаблонов
   *   Могут ссылаться на `source_custom_section_id` или `source_ideal_section_id`

3. **Ребра (Mappings):** Правила переноса данных между секциями
   *   `ideal_mappings` - правила между идеальными секциями
   *   `custom_mappings` - правила для пользовательских шаблонов
   *   Содержат инструкции для AI (`instruction`) - например, "change future to past tense"
   *   Имеют `order_index` для определения порядка применения

### 2.2 Процесс Генерации

При запросе генерации секции через `Writer.generate_section()`:

1. **Context Resolution (Поиск правил):**
   - Находятся все `custom_mappings`, где `target_custom_section_id` равен `custom_section.id`
   - Если нет, ищутся `ideal_mappings` через ссылку `custom_section.ideal_section_id`
   - Правила сортируются по `order_index`

2. **Data Retrieval (Поиск источников):**
   - Для каждого маппинга находятся реальные секции документов проекта
   - Фильтруются только актуальные версии (`is_current_version = TRUE`)
   - Если маппинг ссылается на `source_ideal_section_id`, находятся все `custom_sections` с таким `ideal_section_id`
   - Обрабатываются как файлы, так и `manual_entry` документы

3. **Сборка контекста:**
   - Загружаются глобальные переменные из `study_globals` (Паспорт исследования) и преобразуются в строку формата Bullet-points
   - Объединяются тексты найденных исходных секций (используется `content_markdown`, если доступен, иначе `content_text`)

4. **Генерация:** LLM вызывается с промптом:
   *   **System Message:** Роль медицинского писателя + глобальные данные исследования (строго соблюдать факты)
   *   **User Message:** Исходные данные из Протокола/SAP (заголовок + контент) + инструкции трансформации из маппингов
   *   Дополнительные инструкции: анализ таблиц в Markdown, использование прошедшего времени для завершенных исследований

5. **Update & History:**
   - Результат преобразуется из Markdown в HTML
   - Обновляется `deliverable_section` (контент, статус `draft_ai`, `used_source_section_ids`)
   - Создается запись в `deliverable_section_history` с причиной "AI generation"

### 2.3 Классификация Секций при Парсинге

При парсинге документа с указанным `template_id` (custom_template_id):
1. Для каждой секции документа создается эмбеддинг заголовка
2. Выполняется векторный поиск ближайшей секции в пользовательском шаблоне (custom_sections) через векторные представления
3. Если similarity > 0.85, секция привязывается к шаблону через `custom_section_id` (ссылается на `custom_sections.id`)
4. Классификация выполняется через векторный поиск по эмбеддингам секций шаблонов

## 3. Traceability

*   Каждая сгенерированная секция содержит информацию о том, какие исходные секции использовались:
    *   `GenerationResult.used_source_section_ids` - список UUID использованных секций документов
    *   `GenerationResult.mapping_logic_used` - описание примененного правила маппинга (тип связи, инструкции)
*   Глобальные переменные сохраняют ссылку на исходную секцию через `study_globals.source_section_id`
*   Метаданные парсинга сохраняются в `source_documents.parsing_metadata` для аудита
*   При наличии нескольких версий документов система автоматически использует самую свежую версию (по `created_at`)

## 4. Обработка Ошибок

Сервис `ContentWriter` обрабатывает следующие случаи:

*   **Нет правил маппинга:** Выбрасывает `ValueError("No mapping rules found for this section")`
*   **Исходный контент не найден:** Выбрасывает `ValueError("Source content not found. Please upload and parse the Protocol first.")`
*   **Ошибка LLM:** Выбрасывает `Exception` с описанием ошибки генерации
*   **Глобальные переменные отсутствуют:** Возвращает сообщение "Глобальные переменные исследования не найдены." в контексте, но продолжает генерацию

## 5. Примеры Использования

### 5.1 Использование ContentWriter в коде

```python
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from services.llm import LLMClient
from services.writer import ContentWriter
from database import get_db

async def generate_csr_section(
    project_id: UUID,
    target_section_id: UUID,
    session: AsyncSession
):
    """Генерация секции CSR на основе данных из Протокола."""
    # Инициализация сервисов
    llm_client = LLMClient()
    writer = ContentWriter(llm_client)
    
    # Генерация черновика секции
    result = await writer.generate_section_draft(
        project_id=project_id,
        target_template_section_id=target_section_id,
        session=session
    )
    
    # Результат содержит:
    # - result.content: сгенерированный текст в Markdown
    # - result.used_source_section_ids: список UUID использованных секций
    # - result.mapping_logic_used: описание примененного правила
    
    return result
```

### 5.2 Структура GenerationResult

```python
from services.writer import GenerationResult

# Пример результата генерации
result = GenerationResult(
    content="# Study Design\n\nИсследование было рандомизированным...",
    used_source_section_ids=[
        UUID("123e4567-e89b-12d3-a456-426614174000"),
        UUID("123e4567-e89b-12d3-a456-426614174001")
    ],
    mapping_logic_used=(
        "Mapping from section 123e4567-e89b-12d3-a456-426614174000 "
        "(type: transformation) with instruction: Change future tense to past"
    )
)
```

### 5.3 Интеграция с FastAPI эндпоинтом

Для использования `ContentWriter` в FastAPI эндпоинте можно создать новый эндпоинт:

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from services.llm import LLMClient
from services.writer import ContentWriter
from database import get_db

router = APIRouter()

@router.post("/api/v1/generate-draft")
async def generate_draft(
    project_id: UUID,
    target_section_id: UUID,
    db: AsyncSession = Depends(get_db)
):
    """Генерирует черновик секции с полной информацией для Audit Trail."""
    try:
        llm_client = LLMClient()
        writer = ContentWriter(llm_client)
        
        result = await writer.generate_section_draft(
            project_id=project_id,
            target_template_section_id=target_section_id,
            session=db
        )
        
        return {
            "content": result.content,
            "used_source_section_ids": [str(id) for id in result.used_source_section_ids],
            "mapping_logic_used": result.mapping_logic_used
        }
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

### 5.4 Управление Промптами

Промпты для генерации контента и извлечения данных вынесены во внешний файл `ai_engine/prompts.yaml` для удобства редактирования без изменения Python кода.

#### 5.4.1 Структура prompts.yaml

Файл `prompts.yaml` содержит версионированные промпты, организованные по категориям:

```yaml
version: "1.0"

generation:
  system_role: |
    Ты профессиональный медицинский писатель...
  section_generation: |
    ИСХОДНЫЕ ДАННЫЕ (Из Протокола/SAP)...
  default_instruction: |
    Используй исходные данные для генерации текста...

extraction:
  system_role: |
    Ты - эксперт по медицинским исследованиям...
  extract_globals: |
    Извлеки глобальные переменные исследования...
```

#### 5.4.2 PromptManager

Класс `PromptManager` (singleton) загружает промпты из YAML файла и предоставляет метод `get_prompt(key, **kwargs)` для получения и форматирования промптов:

```python
from services.prompt_manager import PromptManager

prompt_manager = PromptManager()

# Получение промпта с подстановкой переменных
system_prompt = prompt_manager.get_prompt(
    "generation.system_role",
    globals_text=globals_text
)

user_prompt = prompt_manager.get_prompt(
    "generation.section_generation",
    source_content=source_content,
    instruction_text=instruction_text,
    section_title=section_title
)
```

#### 5.4.3 Формат Промптов

**System Prompt (generation.system_role):**
```
Ты профессиональный медицинский писатель.
Твоя задача — написать раздел клинического документа.

ГЛОБАЛЬНЫЕ ДАННЫЕ ИССЛЕДОВАНИЯ (Строго соблюдай эти факты):
{globals_text}

Важно: Используй только факты из глобальных данных исследования. Не придумывай информацию.
```

**User Prompt (generation.section_generation):**
```
ИСХОДНЫЕ ДАННЫЕ (Из Протокола/SAP):

{source_content}

ИНСТРУКЦИЯ:
{instruction_text}

(Дополнительно: Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. Глаголы ставь в прошедшее время, так как исследование завершено.)

Сгенерируй текст для секции "{section_title}" в формате Markdown.
```

**Примечание:** Prompt Engineers могут изменять промпты в файле `prompts.yaml` без необходимости изменения Python кода. Для применения изменений без перезапуска приложения можно использовать метод `prompt_manager.reload()`.
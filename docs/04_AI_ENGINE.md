# 04. AI Engine: Logic & Generation

## 1. Архитектура Сервиса (Python)
*   **Framework:** FastAPI.
*   **Libs:** Docling (parsing), SQLAlchemy (Async) + asyncpg, pgvector (vector search), YandexGPT SDK / OpenAI-compatible client.
*   **Logic:** Structure-RAG с поддержкой Template Graph (Граф Шаблонов).
*   **Архитектура:** Микросервис с Dependency Injection для БД.

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
*   Парсинг выполняется асинхронно в фоне (BackgroundTasks)
*   Автоматическая классификация секций через векторный поиск (если указан `template_id`)
*   Создание эмбеддингов для секций (для гибридного поиска)
*   Сохранение метаданных парсинга (время, количество страниц) в `source_documents.parsing_metadata`

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

#### Эндпоинт `GET /templates`
Возвращает список доступных шаблонов документов с их секциями.

**Ответ:**
```json
[
  {
    "id": "uuid-шаблона",
    "name": "Protocol_EAEU",
    "description": "Протокол исследования (ЕАЭС)",
    "sections": [
      {
        "id": "uuid-секции",
        "title": "3.1 Study Design",
        "section_number": "3.1",
        "is_mandatory": true
      }
    ]
  }
]
```

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

#### Сервис Генератора (`services/writer.py`)

**Класс `SectionWriter`** - генерирует секции документов:
*   `generate_target_section(session, project_id, target_section_id, deliverable_id) -> str` - генерирует целевую секцию на основе Template Graph
*   Ищет исходные данные в таблице `source_sections`
*   Сохраняет результат в таблицу `deliverable_sections`:
     - Записывает сгенерированный текст в поле `content_html`
     - Обновляет статус секции на `generated`
     - Сохраняет ID использованных исходных секций в `used_source_section_ids`
*   Возвращает сгенерированный текст секции в формате Markdown
*   Используется в эндпоинте `POST /generate`

**Класс `ContentWriter`** - сервис генерации контента на основе Template Graph и глобального контекста (рекомендуется):
*   `generate_section_draft(project_id, target_template_section_id, session) -> GenerationResult` - генерирует черновик раздела (например, для CSR) на основе данных из Протокола
*   Возвращает структурированный результат с метаданными для Audit Trail
*   Более строгая обработка ошибок и валидация данных
*   Автоматический выбор самой свежей версии документа при наличии нескольких версий

**Модель `GenerationResult`** (Pydantic) - результат генерации секции:
*   `content: str` - сгенерированный текст секции в формате Markdown
*   `used_source_section_ids: List[UUID]` - список UUID исходных секций, использованных для генерации
*   `mapping_logic_used: str` - описание правила маппинга, которое было применено

**Алгоритм работы `ContentWriter.generate_section_draft`:**
1. **Сбор Глобального Контекста** - извлекает переменные из `study_globals` (Phase, Drug, Population и т.д.) и формирует строку в формате Bullet-points
2. **Обход Графа (Поиск правил)** - находит все записи в `section_mappings`, где `target_section_id == target_template_section_id`
3. **Поиск Реального Контента (Retrieval)** - находит секции в `source_sections`, которые:
   - Принадлежат проекту (`project_id`)
   - Имеют `template_section_id`, совпадающий с `source_section_id` из маппинга
   - Если найдено несколько версий документа, берется самая свежая (по `source_documents.created_at`)
4. **Сборка Промпта** - формирует System и User промпты с глобальным контекстом, исходными данными и инструкциями трансформации
5. **Генерация и Ответ** - вызывает LLM и возвращает `GenerationResult` с контентом и метаданными для Audit Trail

## 2. Template Graph Architecture (Граф Шаблонов)

Система использует архитектуру Template Graph для структурированной генерации документов:

### 2.1 Компоненты Графа

1. **Узлы (Template Sections):** Идеальные прототипы секций документов ("Золотой стандарт")
   *   Хранятся в таблице `template_sections`
   *   Имеют векторные представления (`embedding`) для семантического поиска
   *   Связаны с шаблонами через `template_id`

2. **Ребра (Section Mappings):** Правила переноса данных между секциями
   *   Хранятся в таблице `section_mappings`
   *   Типы связей: `direct_copy`, `summary`, `transformation`, `consistency_check`
   *   Содержат инструкции для AI (`instruction`) - например, "change future to past tense"

### 2.2 Процесс Генерации

При запросе генерации секции (`POST /generate` или через `ContentWriter.generate_section_draft`):

1. **Поиск правил:** Находятся все `section_mappings`, где `target_section_id` равен запрашиваемому
2. **Поиск источников:** Для каждого правила находятся реальные секции документов проекта, привязанные к `source_section_id`
   *   Если найдено несколько версий документа (например, Протокол v1 и v2), берется самая свежая (по `source_documents.created_at`)
3. **Сборка контекста:**
   *   Загружаются глобальные переменные из `study_globals` (Паспорт исследования) и преобразуются в строку формата Bullet-points
   *   Объединяются тексты найденных исходных секций (используется `content_markdown`, если доступен, иначе `content_text`)
4. **Генерация:** LLM вызывается с промптом:
   *   **System Message:** Роль медицинского писателя + глобальные данные исследования (строго соблюдать факты)
   *   **User Message:** Исходные данные из Протокола/SAP (заголовок + контент) + инструкции трансформации из `section_mappings.instruction`
   *   Дополнительные инструкции: анализ таблиц в Markdown, использование прошедшего времени для завершенных исследований
5. **Результат:** Возвращается `GenerationResult` с контентом, списком использованных секций и описанием примененного правила маппинга (для Audit Trail)

### 2.3 Классификация Секций при Парсинге

При парсинге документа с указанным `template_id`:
1. Для каждой секции документа создается эмбеддинг заголовка
2. Выполняется векторный поиск ближайшей секции в шаблоне (cosine similarity)
3. Если similarity > 0.85, секция привязывается к шаблону через `template_section_id`

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

### 5.4 Формат Промптов

**System Prompt:**
```
Ты профессиональный медицинский писатель.
Твоя задача — написать раздел клинического документа.

ГЛОБАЛЬНЫЕ ДАННЫЕ ИССЛЕДОВАНИЯ (Строго соблюдай эти факты):
- **Phase**: Phase III
- **Drug_Name**: Препарат X
- **Population**: Взрослые пациенты с диагнозом Y

Важно: Используй только факты из глобальных данных исследования. Не придумывай информацию.
```

**User Prompt:**
```
ИСХОДНЫЕ ДАННЫЕ (Из Протокола/SAP):

**Заголовок:** 3.1 Дизайн исследования

**Контент:**
Исследование представляет собой рандомизированное...

ИНСТРУКЦИЯ:
Change future tense to past tense. If you see a table in Markdown, analyze it and describe key data as text.

(Дополнительно: Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. Глаголы ставь в прошедшее время, так как исследование завершено.)

Сгенерируй только текст итогового раздела (в формате Markdown).
```
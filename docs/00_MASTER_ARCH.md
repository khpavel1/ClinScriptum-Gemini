# 00. Master Architecture & Tech Stack

## Обзор
Система для подготовки регуляторной и медицинской документации (CSR, Protocols) с использованием архитектуры **Deterministic Structure-RAG**.
Система разделена на "Легкий фронтенд" (Next.js) и "Тяжелый AI-движок" (Python), что позволяет использовать продвинутые библиотеки парсинга и соответствовать требованиям по защите данных (российский стек/On-Prem ready).

Уровни зрелости: **MVP** (Supabase Cloud + Local Python) -> **Prod** (Yandex Cloud / On-Prem).

## Технический Стек
### Frontend & App Logic (User Interface)
*   **Framework:** Next.js 14+ (App Router).
*   **UI:** Shadcn/ui, Tailwind CSS, Lucide React.
*   **Editor:** Tiptap (Headless).
*   **Auth/DB Proxy:** Supabase (PostgreSQL, GoTrue Auth, Storage).

### AI Engine (Microservice)
*   **Runtime:** Python 3.10+ (FastAPI).
*   **Parsing (OCR):** Модульная архитектура парсеров:
    *   Базовый класс: `BaseParser` (абстрактный интерфейс)
    *   Реализации: `DoclingParser` (по умолчанию), `AzureParser` (планируется)
    *   Поддержка переключения парсера без изменения логики работы с БД
*   **Content Generation:** Сервисы генерации контента (`Writer`, `SectionWriter`, `ContentWriter`):
    *   `Writer` - основной сервис для генерации секций на основе пользовательских шаблонов (custom_templates)
    *   Использует двухуровневую архитектуру шаблонов (Ideal/Custom) для поиска правил маппинга
    *   Интегрирует глобальный контекст исследования (Study Globals)
    *   Возвращает результат с метаданными для Audit Trail (`GenerationResult`)
    *   Автоматически создает записи истории изменений (`deliverable_section_history`)
*   **LLM:** **YandexGPT Pro** (API) или **Qwen 2.5** (Self-hosted vLLM).
*   **Orchestration:** LangChain / LiteLLM.

## Глобальная Архитектура БД (High Level)
Схема адаптирована под структурный RAG и глобальный контекст с двухуровневой системой шаблонов.

1.  **Organizations & Users:** Стандартная схема Supabase (RBAC).
2.  **Projects:** Исследования.
3.  **SourceDocuments:** Метаданные файлов с поддержкой версионирования (`parent_document_id`, `is_current_version`).
4.  **SourceSections (Вместо RagChunks):**
    *   Хранит структуру: Заголовок, Номер секции, Контент (Markdown), Таблицы.
    *   Поле `embedding` (vector) для гибридного поиска.
    *   Связь с пользовательскими шаблонами через `custom_section_id` (custom_sections).
5.  **Двухуровневая система шаблонов:**
    *   **Ideal Templates (System Master Data):** Золотые стандарты структур (`ideal_templates`, `ideal_sections`, `ideal_mappings`).
    *   **Custom Templates (Configuration):** Пользовательские настройки на основе идеальных (`custom_templates`, `custom_sections`, `custom_mappings`).
    *   Могут быть глобальными для организации или специфичными для проекта.
6.  **Deliverables & DeliverableSections:**
    *   Готовые документы (Outputs), созданные на основе пользовательских шаблонов.
    *   DeliverableSection содержит HTML контент для редактора, workflow статусы (`empty`, `draft_ai`, `in_progress`, `review`, `approved`) и ссылки на использованные source_sections.
    *   Поддержка блокировок (`locked_by_user_id`, `locked_at`) и истории изменений (`deliverable_section_history`).
7.  **StudyGlobals (Global Context):**
    *   "Паспорт исследования": Фаза, Препарат, Популяция и т.д.
    *   Извлекается автоматически из Синопсиса.
    *   Ссылка на исходную секцию через `source_section_id`.

## Принципы Разработки
1.  **Structure First:** Мы не режем текст на случайные куски. Мы парсим структуру документа (Заголовки, Таблицы).
2.  **Global Understanding:** Перед генерацией любой секции в контекст подается "Паспорт исследования".
3.  **Hybrid Processing:** Next.js управляет UI, Python управляет данными и AI.
4.  **Extensibility:** Архитектура парсеров позволяет легко добавлять новые реализации (Azure, Surya и т.д.) без изменения основной логики.
5.  **Two-Level Template System:** Разделение на идеальные шаблоны (золотые стандарты) и пользовательские шаблоны (настройки проектов).
6.  **Versioning & Audit Trail:** Поддержка версионирования документов и полная история изменений секций для отслеживаемости.
7.  **Workflow Management:** Четкий workflow статусов секций с блокировками для предотвращения конфликтов редактирования.
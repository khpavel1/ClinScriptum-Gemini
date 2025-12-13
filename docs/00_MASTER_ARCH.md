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
*   **LLM:** **YandexGPT Pro** (API) или **Qwen 2.5** (Self-hosted vLLM).
*   **Orchestration:** LangChain / LiteLLM.

## Глобальная Архитектура БД (High Level)
Схема адаптирована под структурный RAG и глобальный контекст.

1.  **Organizations & Users:** Стандартная схема Supabase (RBAC).
2.  **Projects:** Исследования.
3.  **SourceDocuments:** Метаданные файлов.
4.  **DocumentSections (Вместо RagChunks):**
    *   Хранит структуру: Заголовок, Номер секции, Контент (Markdown), Таблицы.
    *   Поле `embedding` (vector) для гибридного поиска.
5.  **StudyGlobals (Global Context):**
    *   "Паспорт исследования": Фаза, Препарат, Популяция и т.д.
    *   Извлекается автоматически из Синопсиса.
6.  **MappingRules:** Правила переноса данных (Протокол -> CSR).

## Принципы Разработки
1.  **Structure First:** Мы не режем текст на случайные куски. Мы парсим структуру документа (Заголовки, Таблицы).
2.  **Global Understanding:** Перед генерацией любой секции в контекст подается "Паспорт исследования".
3.  **Hybrid Processing:** Next.js управляет UI, Python управляет данными и AI.
4.  **Extensibility:** Архитектура парсеров позволяет легко добавлять новые реализации (Azure, Surya и т.д.) без изменения основной логики.
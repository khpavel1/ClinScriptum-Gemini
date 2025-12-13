# ClinScriptum-Gemini

Система для подготовки регуляторной и медицинской документации (CSR, Protocols) с использованием архитектуры **Deterministic Structure-RAG**.

## Репозиторий

Проект размещен на GitHub: [https://github.com/khpavel1/ClinScriptum-Gemini.git](https://github.com/khpavel1/ClinScriptum-Gemini.git)

## Обзор

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
*   **LLM:** **YandexGPT Pro** (API) или **Qwen 2.5** (Self-hosted vLLM).
*   **Orchestration:** LangChain / LiteLLM.

## Документация

Подробная документация находится в папке `docs/`:

- [00_MASTER_ARCH.md](docs/00_MASTER_ARCH.md) - Общая архитектура и технический стек
- [01_AUTH_PROJECTS.md](docs/01_AUTH_PROJECTS.md) - Аутентификация и управление проектами
- [02_DATA_RAG.md](docs/02_DATA_RAG.md) - Работа с данными и RAG
- [03_EDITOR_CORE.md](docs/03_EDITOR_CORE.md) - Редактор документов
- [04_AI_ENGINE.md](docs/04_AI_ENGINE.md) - AI движок
- [05_QC_COMPLIANCE.md](docs/05_QC_COMPLIANCE.md) - Контроль качества и соответствие
- [06_EXPORT.md](docs/06_EXPORT.md) - Экспорт документов

## Установка

### Требования
- Node.js 18+
- Python 3.10+
- Supabase аккаунт

### Frontend
```bash
npm install
npm run dev
```

### AI Engine
```bash
cd ai_engine
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Принципы Разработки

1.  **Structure First:** Мы не режем текст на случайные куски. Мы парсим структуру документа (Заголовки, Таблицы).
2.  **Global Understanding:** Перед генерацией любой секции в контекст подается "Паспорт исследования".
3.  **Hybrid Processing:** Next.js управляет UI, Python управляет данными и AI.
4.  **Extensibility:** Архитектура парсеров позволяет легко добавлять новые реализации без изменения основной логики.

## Лицензия

Проект находится в разработке.

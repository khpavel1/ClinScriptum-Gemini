# Структура проекта ClinScriptum-Gemini

Данный документ описывает структуру файлов и директорий проекта ClinScriptum-Gemini.

## Общая структура

Проект разделен на два основных компонента:
- **Frontend** (Next.js приложение) - пользовательский интерфейс
- **AI Engine** (Python микросервис) - обработка документов и AI-функциональность

## Корневая директория

```
.
├── .cursor/                    # Настройки Cursor IDE
├── .gitignore                  # Игнорируемые файлы Git
├── docker-compose.yml          # Конфигурация Docker для локальной БД
├── package.json                # Зависимости и скрипты Node.js
├── package-lock.json           # Зафиксированные версии зависимостей
├── postcss.config.mjs          # Конфигурация PostCSS
├── tsconfig.json               # Конфигурация TypeScript
├── next-env.d.ts               # Типы окружения Next.js
├── middleware.ts               # Middleware для аутентификации
├── components.json              # Конфигурация shadcn/ui
├── README.md                   # Основная документация проекта
├── schema_organizations_profiles_projects.sql  # SQL схема для организаций, профилей и проектов
│
├── app/                        # Next.js App Router (Frontend)
├── components/                 # React компоненты
├── lib/                        # Утилиты и библиотеки
├── types/                      # TypeScript типы
├── ai_engine/                  # Python микросервис (AI Engine)
└── docs/                       # Документация проекта
```

## Frontend (Next.js)

### `app/` - App Router структура

Директория содержит маршруты приложения, использующие Next.js App Router:

```
app/
├── layout.tsx                  # Корневой layout приложения
├── globals.css                 # Глобальные стили
├── login/                      # Страница входа
│   ├── page.tsx                # Компонент страницы входа
│   └── actions.ts              # Server Actions для аутентификации
├── dashboard/                  # Дашборд пользователя
│   ├── page.tsx                # Главная страница дашборда
│   └── actions.ts              # Server Actions для дашборда
└── projects/                   # Управление проектами
    └── [id]/                   # Динамический маршрут для проекта
        ├── page.tsx            # Страница проекта (использует ProjectView)
        └── actions.ts          # Server Actions для работы с проектом
```

**Описание файлов:**
- `layout.tsx` - корневой layout, определяет структуру HTML и подключает глобальные стили
- `globals.css` - глобальные CSS стили для всего приложения
- `login/page.tsx` - страница входа в систему
- `login/actions.ts` - серверные действия для обработки аутентификации
- `dashboard/page.tsx` - главная страница дашборда после входа
- `dashboard/actions.ts` - серверные действия для работы с дашбордом
- `projects/[id]/page.tsx` - динамическая страница для просмотра и редактирования проекта, использует компонент `ProjectView`
- `projects/[id]/actions.ts` - серверные действия для работы с проектом:
  - `uploadSourceAction` - загрузка исходных документов в Supabase Storage и запуск парсинга через AI Engine
  - `createDeliverableAction` - создание нового документа (deliverable) на основе шаблона с автоматическим созданием пустых секций

### `components/` - React компоненты

```
components/
├── ui/                         # Базовые UI компоненты (shadcn/ui)
│   ├── avatar.tsx
│   ├── badge.tsx
│   ├── breadcrumb.tsx
│   ├── button.tsx
│   ├── card.tsx
│   ├── dialog.tsx
│   ├── form.tsx
│   ├── input.tsx
│   ├── label.tsx
│   ├── progress.tsx
│   ├── select.tsx
│   ├── tabs.tsx
│   └── textarea.tsx
│
├── login-form.tsx              # Форма входа
├── create-project-dialog.tsx   # Диалог создания проекта
├── project-view.tsx            # Основной компонент отображения проекта
├── project-header.tsx          # Заголовок проекта
├── project-overview-tab.tsx    # Вкладка обзора проекта
├── project-documents-tab.tsx  # Вкладка документов проекта
├── project-source-documents-tab.tsx  # Вкладка исходных документов
├── project-qc-issues-tab.tsx  # Вкладка проблем контроля качества
├── project-settings-tab.tsx   # Вкладка настроек проекта
├── project-filter.tsx          # Фильтр проектов
├── create-deliverable-modal.tsx  # Модальное окно создания документа
└── upload-source-modal.tsx     # Модальное окно загрузки исходного документа
```

**Описание:**
- `ui/` - переиспользуемые UI компоненты на основе shadcn/ui и Radix UI
- `project-view.tsx` - основной компонент для отображения проекта, объединяет все вкладки и модальные окна
- `create-deliverable-modal.tsx` - модальное окно для создания новых документов (deliverables) на основе шаблонов
- `upload-source-modal.tsx` - модальное окно для загрузки исходных документов (Protocol, SAP и т.д.) с поддержкой drag-and-drop
- Остальные компоненты - специфичные для приложения компоненты, связанные с проектами и аутентификацией

### `lib/` - Утилиты и библиотеки

```
lib/
├── supabase/
│   ├── client.ts               # Клиент Supabase для клиентской стороны
│   └── server.ts               # Клиент Supabase для серверной стороны
└── utils.ts                    # Общие утилиты (cn, и т.д.)
```

**Описание:**
- `supabase/client.ts` - инициализация Supabase клиента для использования в клиентских компонентах
- `supabase/server.ts` - инициализация Supabase клиента для Server Components и Server Actions
- `utils.ts` - вспомогательные функции (например, функция `cn` для объединения классов)

### `types/` - TypeScript типы

```
types/
└── database.types.ts           # Автоматически сгенерированные типы из Supabase
```

**Описание:**
- `database.types.ts` - типы TypeScript, автоматически сгенерированные из схемы Supabase базы данных

### Конфигурационные файлы Frontend

- `package.json` - зависимости Node.js и npm скрипты
- `tsconfig.json` - конфигурация TypeScript компилятора
- `postcss.config.mjs` - конфигурация PostCSS для обработки CSS
- `components.json` - конфигурация shadcn/ui компонентов
- `middleware.ts` - Next.js middleware для защиты маршрутов и управления аутентификацией

## AI Engine (Python микросервис)

### `ai_engine/` - Python сервис

```
ai_engine/
├── main.py                     # Точка входа FastAPI приложения
├── config.py                   # Конфигурация приложения (настройки)
├── database.py                 # Подключение к базе данных
├── models.py                   # SQLAlchemy модели
├── requirements.txt            # Python зависимости
└── services/                   # Бизнес-логика и сервисы
    ├── __init__.py
    ├── base_parser.py          # Базовый абстрактный класс парсера
    ├── docling_parser.py      # Реализация парсера на основе Docling
    ├── parser.py               # Основная логика парсинга документов
    ├── classifier.py           # Классификация секций документов
    ├── extractor.py            # Извлечение данных из документов
    ├── llm.py                  # Клиент для работы с LLM (YandexGPT/Qwen)
    ├── writer.py               # Генерация текста секций
    └── types.py                # Типы данных для сервисов
```

**Описание файлов:**

- `main.py` - главный файл FastAPI приложения:
  - Настройка CORS
  - Определение API эндпоинтов:
    - `POST /api/v1/parse` - запуск парсинга документа в фоне с сохранением в БД
    - `POST /generate` - генерация секции документа на основе Template Graph
    - `GET /health` - проверка работоспособности сервиса
  - Управление жизненным циклом приложения (lifespan)
  - Интеграция всех сервисов

- `config.py` - конфигурация:
  - Настройки подключения к БД
  - API ключи для LLM
  - Параметры приложения

- `database.py` - работа с базой данных:
  - Инициализация SQLAlchemy
  - Управление сессиями
  - Подключение к PostgreSQL

- `models.py` - SQLAlchemy ORM модели:
  - Модели таблиц базы данных с поддержкой Template Graph Architecture:
    - **Ideal Layer:** `IdealTemplate`, `IdealSection`, `IdealMapping`
    - **Custom Layer:** `CustomTemplate`, `CustomSection`, `CustomMapping`
    - **Source Layer:** `SourceDocument`, `SourceSection`, `StudyGlobal`
    - **Deliverable Layer:** `Deliverable`, `DeliverableSection`, `DeliverableSectionHistory`
  - Связи между таблицами через SQLAlchemy relationships
  - Поддержка pgvector для векторных полей (embeddings)

- `services/base_parser.py` - абстрактный базовый класс для парсеров документов

- `services/docling_parser.py` - конкретная реализация парсера на основе Docling

- `services/parser.py` - основная логика обработки документов

- `services/classifier.py` - классификация секций документов по типам

- `services/extractor.py` - извлечение структурированных данных из документов

- `services/llm.py` - клиент для взаимодействия с языковыми моделями (YandexGPT Pro или Qwen 2.5)

- `services/writer.py` - генерация текста секций документов с использованием LLM:
  - `Writer` - основной сервис генерации на основе пользовательских шаблонов (custom_templates):
    - Метод `generate_section()` - генерирует секцию для существующей `deliverable_section`
    - Использует двухуровневую архитектуру шаблонов (Ideal/Custom) для поиска правил маппинга
    - Интегрирует глобальный контекст исследования (Study Globals)
    - Автоматически создает записи истории изменений (`deliverable_section_history`)
    - Фильтрует только актуальные версии документов (`is_current_version = TRUE`)
  - `ContentWriter` - генератор с полной поддержкой Template Graph (рекомендуется для новых интеграций):
    - Метод `generate_section_draft()` - генерирует черновик раздела на основе данных из Протокола
    - Возвращает структурированный результат с метаданными для Audit Trail
  - `GenerationResult` - модель результата генерации с метаданными для Audit Trail

- `services/types.py` - типы данных и модели Pydantic для сервисов

- `requirements.txt` - список Python зависимостей с версиями

## Документация

### `docs/` - Документация проекта

```
docs/
├── 00_MASTER_ARCH.md           # Общая архитектура системы
├── 01_AUTH_PROJECTS.md         # Аутентификация и управление проектами
├── 02_DATA_RAG.md              # Работа с данными и RAG
├── 03_EDITOR_CORE.md           # Редактор документов
├── 04_AI_ENGINE.md             # AI движок
├── 05_QC_COMPLIANCE.md         # Контроль качества и соответствие
├── 06_EXPORT.md                # Экспорт документов
├── 07_PROJECT_STRUCTURE.md     # Структура проекта (этот документ)
└── schema.sql                  # Полная SQL схема базы данных
```

**Описание:**
- Документация разделена по функциональным областям
- `schema.sql` - полная схема базы данных PostgreSQL с расширением pgvector

## Конфигурация Cursor IDE

### `.cursor/` - Настройки Cursor

```
.cursor/
├── rules/
│   ├── context7.mdc            # Правила использования Context7 для документации библиотек
│   └── update-docs.mdc         # Правила обновления документации
└── commands/                   # Пользовательские команды Cursor
    ├── speckit.analyze.md
    ├── speckit.checklist.md
    ├── speckit.clarify.md
    ├── speckit.constitution.md
    ├── speckit.implement.md
    ├── speckit.plan.md
    ├── speckit.specify.md
    ├── speckit.tasks.md
    └── speckit.taskstoissues.md
```

## Docker

### `docker-compose.yml`

Конфигурация для запуска локальной PostgreSQL базы данных с расширением pgvector:
- Образ: `pgvector/pgvector:0.8.1-pg18-trixie`
- Порт: 5432
- Персистентное хранилище данных

## Взаимодействие компонентов

```
┌─────────────────┐
│   Next.js App   │  (Frontend)
│   (app/,        │
│   components/)  │
└────────┬────────┘
         │ HTTP/REST API
         │
         ▼
┌─────────────────┐
│  Supabase       │  (Auth, DB, Storage)
│  PostgreSQL     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AI Engine      │  (Python/FastAPI)
│  (ai_engine/)   │
└─────────────────┘
```

**Поток данных:**
1. Пользователь взаимодействует с Next.js приложением
2. Next.js обращается к Supabase для аутентификации и работы с БД
3. Для обработки документов Next.js отправляет запросы к AI Engine
4. AI Engine обрабатывает документы, использует LLM и сохраняет результаты в БД через Supabase
5. Next.js отображает результаты пользователю

## Зависимости

### Frontend (Node.js)
- **Next.js 16+** - React фреймворк с App Router
- **React 19** - UI библиотека
- **Supabase** - Backend as a Service (БД, Auth, Storage)
- **shadcn/ui** - UI компоненты на основе Radix UI
- **Tailwind CSS** - CSS фреймворк
- **TypeScript** - типизированный JavaScript

### AI Engine (Python)
- **FastAPI** - веб-фреймворк для API
- **SQLAlchemy** - ORM для работы с БД
- **Docling** - парсинг документов
- **LangChain/LiteLLM** - оркестрация LLM
- **YandexGPT Pro / Qwen 2.5** - языковые модели

## Примечания

- Проект использует гибридную архитектуру: легкий фронтенд на Next.js и тяжелый AI-движок на Python
- Все изменения кода должны сопровождаться обновлением документации в `docs/`
- Документация пишется на русском языке, комментарии в Python коде - на английском


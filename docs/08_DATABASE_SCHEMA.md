# 08. Структура базы данных

## Обзор

База данных построена на PostgreSQL с использованием расширений `pgvector` для работы с векторными эмбеддингами и `pgcrypto` для генерации UUID. Архитектура поддерживает мультитенантность через организации и реализует Row Level Security (RLS) для изоляции данных между клиентами.

## Расширения PostgreSQL

- **pgvector** - работа с векторными эмбеддингами (размерность 1536)
- **pgcrypto** - криптографические функции
- **uuid-ossp** - генерация UUID
- **pg_stat_statements** - статистика выполнения запросов
- **supabase_vault** - безопасное хранение секретов
- **pg_graphql** - GraphQL API

## ENUM типы

### `input_type_enum`
Тип входных данных для документов-источников.

Возможные значения:
- `'file'` - файл (загруженный документ)
- `'manual_entry'` - ручной ввод

### `deliverable_section_status_enum`
Статус секции готового документа в workflow.

Возможные значения:
- `'empty'` - пустая секция (только что создана)
- `'draft_ai'` - секция сгенерирована AI (черновик)
- `'in_progress'` - секция в процессе редактирования
- `'review'` - секция на проверке
- `'approved'` - секция одобрена

## Основные сущности

### 1. Пользователи и организации (Multi-tenant)

#### Таблица `organizations`
Мультитенантные организации для изоляции данных клиентов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор организации |
| `name` | TEXT | Название организации |
| `slug` | TEXT (UNIQUE) | URL-friendly идентификатор организации |
| `created_by` | UUID (FK → auth.users) | Пользователь, создавший организацию |
| `created_at` | TIMESTAMPTZ | Время создания |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Индексы:**
- `idx_organizations_slug` - по полю `slug`
- `idx_organizations_created_by` - по полю `created_by`

**Триггеры:**
- `update_organizations_updated_at` - автоматическое обновление `updated_at`
- `auto_assign_org_admin_trigger` - автоматическое назначение создателя как админа организации

#### Таблица `profiles`
Профили пользователей, расширение таблицы `auth.users` из Supabase.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK, FK → auth.users) | Идентификатор пользователя (связь с auth.users) |
| `email` | TEXT | Email пользователя |
| `full_name` | TEXT | Полное имя пользователя |
| `avatar_url` | TEXT | URL аватара пользователя |
| `organization_id` | UUID (FK → organizations) | Основная организация пользователя (может быть NULL) |
| `created_at` | TIMESTAMPTZ | Время создания профиля |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Индексы:**
- `idx_profiles_organization_id` - по полю `organization_id`
- `idx_profiles_email` - по полю `email`

**Триггеры:**
- `update_profiles_updated_at` - автоматическое обновление `updated_at`

#### Таблица `organization_members`
Участники организаций с ролями.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор |
| `organization_id` | UUID (FK → organizations) | Идентификатор организации |
| `user_id` | UUID (FK → profiles) | Идентификатор пользователя |
| `role` | TEXT | Роль: `org_admin` или `member` |
| `created_at` | TIMESTAMPTZ | Время добавления в организацию |

**Ограничения:**
- `UNIQUE(organization_id, user_id)` - пользователь может быть в организации только один раз
- `CHECK (role IN ('org_admin', 'member'))` - валидация роли

**Индексы:**
- `idx_org_members_org_id` - по полю `organization_id`
- `idx_org_members_user_id` - по полю `user_id`
- `idx_org_members_role` - составной индекс по `(organization_id, role)`

### 2. Проекты и исследования

#### Таблица `projects`
Исследования/проекты, привязанные к организациям.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор проекта |
| `organization_id` | UUID (FK → organizations) | Идентификатор организации |
| `study_code` | TEXT | Уникальный код исследования в рамках организации |
| `title` | TEXT | Название проекта |
| `sponsor` | TEXT | Спонсор исследования |
| `therapeutic_area` | TEXT | Терапевтическая область |
| `status` | TEXT | Статус: `draft`, `active`, `archived` |
| `created_by` | UUID (FK → profiles) | Пользователь, создавший проект |
| `created_at` | TIMESTAMPTZ | Время создания |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Ограничения:**
- `UNIQUE(organization_id, study_code)` - уникальность кода исследования в рамках организации
- `CHECK (status IN ('draft', 'active', 'archived'))` - валидация статуса

**Индексы:**
- `idx_projects_organization_id` - по полю `organization_id`
- `idx_projects_status` - по полю `status`
- `idx_projects_study_code` - по полю `study_code`
- `idx_projects_created_by` - по полю `created_by`

**Триггеры:**
- `update_projects_updated_at` - автоматическое обновление `updated_at`
- `auto_assign_project_owner_trigger` - автоматическое назначение создателя как владельца проекта

#### Таблица `project_members`
Участники проектов с ролями.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор |
| `project_id` | UUID (FK → projects) | Идентификатор проекта |
| `user_id` | UUID (FK → profiles) | Идентификатор пользователя |
| `role` | TEXT | Роль: `project_owner`, `editor`, `viewer` |
| `created_at` | TIMESTAMPTZ | Время добавления в проект |

**Ограничения:**
- `UNIQUE(project_id, user_id)` - пользователь может быть в проекте только один раз
- `CHECK (role IN ('project_owner', 'editor', 'viewer'))` - валидация роли

**Индексы:**
- `idx_project_members_project_id` - по полю `project_id`
- `idx_project_members_user_id` - по полю `user_id`
- `idx_project_members_role` - составной индекс по `(project_id, role)`

### 3. Документы и секции (RAG)

#### Таблица `source_documents`
Метаданные исходных документов (Protocol, SAP, CSR и т.д.) с поддержкой версионирования.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор документа |
| `project_id` | UUID (FK → projects) | Идентификатор проекта |
| `template_id` | UUID (FK → custom_templates) | Пользовательский шаблон для классификации документа |
| `name` | TEXT | Название документа |
| `storage_path` | TEXT | Путь к файлу в Supabase Storage (устаревшее, использовать `file_path`) |
| `file_path` | TEXT | Путь к файлу (может быть NULL для ручного ввода) |
| `input_type` | input_type_enum | Тип ввода: `file` (файл) или `manual_entry` (ручной ввод) |
| `doc_type` | TEXT | Тип документа (Protocol, SAP, CSR и т.д.) |
| `status` | TEXT | Статус обработки: `uploading`, `indexed`, `error` |
| `parent_document_id` | UUID (FK → source_documents) | Родительский документ для версионирования |
| `version_label` | TEXT | Метка версии (например, "v1.0", "v2.1") |
| `is_current_version` | BOOLEAN | Является ли эта версия текущей (default: true) |
| `parsing_metadata` | JSONB | Технические метаданные парсинга (время, количество страниц, ошибки) |
| `parsing_quality_score` | INTEGER | Ручная оценка качества парсинга (1-5) |
| `parsing_quality_comment` | TEXT | Комментарий к оценке качества |
| `detected_tables_count` | INTEGER | Количество таблиц, обнаруженных парсером |
| `created_at` | TIMESTAMPTZ | Время загрузки документа |

**Индексы:**
- `idx_source_documents_project_id` - по полю `project_id`
- `idx_source_documents_template_id` - по полю `template_id`
- `idx_source_documents_status` - по полю `status`
- `idx_source_documents_doc_type` - по полю `doc_type`
- `idx_source_documents_parent_document_id` - по полю `parent_document_id`
- `idx_source_documents_is_current_version` - по полю `is_current_version`
- `idx_source_documents_input_type` - по полю `input_type`

#### Таблица `source_sections`
Секции исходных документов (Inputs) с классификацией по пользовательским шаблонам и координатами для подсветки.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `document_id` | UUID (FK → source_documents) | Идентификатор документа |
| `custom_section_id` | UUID (FK → custom_sections) | Связь с секцией пользовательского шаблона (может быть NULL) |
| `section_number` | TEXT | Номер секции (например, "3.1.2") |
| `header` | TEXT | Заголовок секции |
| `page_number` | INTEGER | Номер страницы |
| `content_text` | TEXT | Чистый текст для поиска |
| `content_markdown` | TEXT | Текст с разметкой таблиц (для LLM) |
| `embedding` | vector(1536) | Векторное представление секции для семантического поиска |
| `classification_confidence` | FLOAT | Уверенность автоматической классификации (0.0-1.0) |
| `bbox` | JSONB | Координаты текста в формате JSONB: `{"page": 1, "x": 100, "y": 200, "w": 300, "h": 50}` для подсветки в PDF |
| `created_at` | TIMESTAMPTZ | Время создания секции |

**Индексы:**
- `idx_source_sections_document_id` - по полю `document_id`
- `idx_source_sections_custom_section_id` - по полю `custom_section_id`
- `idx_source_sections_embedding` - векторный индекс (IVFFlat) для семантического поиска
- `idx_source_sections_bbox` - GIN индекс для JSONB поля `bbox`

### 5. Слой "Идеальные Шаблоны" (System Master Data)

> **Примечание:** Старая одноуровневая система шаблонов (`doc_templates`, `template_sections`, `section_mappings`) была удалена и заменена на двухуровневую архитектуру. См. раздел ниже.

### 6. Слой "Идеальные Шаблоны" (System Master Data)

Золотые стандарты структур документов, доступные всем пользователям системы.

#### Таблица `ideal_templates`
Идеальные шаблоны (золотые стандарты) с версионированием.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор шаблона |
| `name` | TEXT | Название идеального шаблона (например, "Protocol_EAEU", "CSR_ICH_E3") |
| `version` | INTEGER | Версия шаблона |
| `is_active` | BOOLEAN | Активен ли шаблон (можно отключить старые версии) |
| `group_id` | UUID | ID группы для связывания версий одного шаблона |
| `created_at` | TIMESTAMPTZ | Время создания шаблона |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Ограничения:**
- `UNIQUE(name, version)` - уникальность комбинации имени и версии

**Индексы:**
- `idx_ideal_templates_group_id` - по полю `group_id`
- `idx_ideal_templates_name` - по полю `name`
- `idx_ideal_templates_is_active` - по полю `is_active`

**Триггеры:**
- `update_ideal_templates_updated_at` - автоматическое обновление `updated_at`

#### Таблица `ideal_sections`
Секции идеальных шаблонов (золотые стандарты структур).

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `template_id` | UUID (FK → ideal_templates) | Связь с идеальным шаблоном |
| `parent_id` | UUID (FK → ideal_sections) | Родительская секция для построения древовидной структуры |
| `title` | TEXT | Название секции |
| `order_index` | INTEGER | Порядок отображения секции в шаблоне |
| `embedding` | vector(1536) | Векторное представление секции для семантического поиска |
| `created_at` | TIMESTAMPTZ | Время создания секции |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Индексы:**
- `idx_ideal_sections_template_id` - по полю `template_id`
- `idx_ideal_sections_parent_id` - по полю `parent_id`
- `idx_ideal_sections_order_index` - составной индекс по `(template_id, order_index)`
- `idx_ideal_sections_embedding` - векторный индекс (IVFFlat) для семантического поиска

**Триггеры:**
- `update_ideal_sections_updated_at` - автоматическое обновление `updated_at`

#### Таблица `ideal_mappings`
Правила переноса данных между идеальными секциями.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор маппинга |
| `target_ideal_section_id` | UUID (FK → ideal_sections) | Целевая идеальная секция |
| `source_ideal_section_id` | UUID (FK → ideal_sections) | Исходная идеальная секция |
| `instruction` | TEXT | Промпт для AI при трансформации данных между секциями |
| `order_index` | INTEGER | Порядок применения маппинга |
| `created_at` | TIMESTAMPTZ | Время создания маппинга |

**Ограничения:**
- `CHECK (target_ideal_section_id != source_ideal_section_id)` - предотвращение петель

**Индексы:**
- `idx_ideal_mappings_target` - по полю `target_ideal_section_id`
- `idx_ideal_mappings_source` - по полю `source_ideal_section_id`
- `idx_ideal_mappings_order` - составной индекс по `(target_ideal_section_id, order_index)`

### 7. Слой "Пользовательские Шаблоны" (Configuration)

Пользовательские настройки шаблонов на основе идеальных шаблонов. Могут быть глобальными для организации или специфичными для проекта.

#### Таблица `custom_templates`
Пользовательские шаблоны (настройки проектов).

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор шаблона |
| `base_ideal_template_id` | UUID (FK → ideal_templates) | Базовый идеальный шаблон |
| `project_id` | UUID (FK → projects) | Проект (NULL для глобальных шаблонов организации) |
| `name` | TEXT | Название пользовательского шаблона |
| `created_at` | TIMESTAMPTZ | Время создания шаблона |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Индексы:**
- `idx_custom_templates_base_ideal` - по полю `base_ideal_template_id`
- `idx_custom_templates_project_id` - по полю `project_id`

**Триггеры:**
- `update_custom_templates_updated_at` - автоматическое обновление `updated_at`

#### Таблица `custom_sections`
Секции пользовательских шаблонов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `custom_template_id` | UUID (FK → custom_templates) | Пользовательский шаблон |
| `ideal_section_id` | UUID (FK → ideal_sections) | Связь с идеальной секцией (может быть NULL для полностью кастомных секций) |
| `parent_id` | UUID (FK → custom_sections) | Родительская секция для построения древовидной структуры (может быть NULL) |
| `title` | TEXT | Название пользовательской секции |
| `order_index` | INTEGER | Порядок отображения секции |
| `created_at` | TIMESTAMPTZ | Время создания секции |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Индексы:**
- `idx_custom_sections_custom_template_id` - по полю `custom_template_id`
- `idx_custom_sections_ideal_section_id` - по полю `ideal_section_id`
- `idx_custom_sections_parent_id` - по полю `parent_id`
- `idx_custom_sections_order_index` - составной индекс по `(custom_template_id, order_index)`

**Триггеры:**
- `update_custom_sections_updated_at` - автоматическое обновление `updated_at`

#### Таблица `custom_mappings`
Правила переноса данных для пользовательских шаблонов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор маппинга |
| `target_custom_section_id` | UUID (FK → custom_sections) | Целевая пользовательская секция |
| `target_ideal_section_id` | UUID (FK → ideal_sections) | Целевая идеальная секция (или NULL) |
| `source_custom_section_id` | UUID (FK → custom_sections) | Исходная пользовательская секция (или NULL) |
| `source_ideal_section_id` | UUID (FK → ideal_sections) | Исходная идеальная секция (или NULL, взаимоисключающее с `source_custom_section_id`) |
| `instruction` | TEXT | Промпт для AI при трансформации данных |
| `order_index` | INTEGER | Порядок применения маппинга |
| `created_at` | TIMESTAMPTZ | Время создания маппинга |

**Ограничения:**
- `CHECK ((source_custom_section_id IS NOT NULL AND source_ideal_section_id IS NULL) OR (source_custom_section_id IS NULL AND source_ideal_section_id IS NOT NULL))` - должен быть указан один из источников

**Индексы:**
- `idx_custom_mappings_target` - по полю `target_custom_section_id`
- `idx_custom_mappings_target_ideal` - по полю `target_ideal_section_id`
- `idx_custom_mappings_source_custom` - по полю `source_custom_section_id`
- `idx_custom_mappings_source_ideal` - по полю `source_ideal_section_id`
- `idx_custom_mappings_order` - составной индекс по `(target_custom_section_id, order_index)`

### 8. Глобальный контекст исследования

#### Таблица `study_globals`
Глобальные переменные исследования (Паспорт исследования).

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор |
| `project_id` | UUID (FK → projects) | Идентификатор проекта |
| `variable_name` | TEXT | Название переменной (например, "Phase", "Drug_Name") |
| `variable_value` | TEXT | Значение переменной |
| `source_section_id` | UUID (FK → source_sections) | Ссылка на секцию исходного документа, из которой извлечена переменная |
| `created_at` | TIMESTAMPTZ | Время создания записи |

**Индексы:**
- Неявные индексы через внешние ключи

### 9. Готовые документы (Deliverables / Outputs)

#### Таблица `deliverables`
Готовые документы (Outputs/Deliverables), созданные на основе пользовательских шаблонов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор документа |
| `project_id` | UUID (FK → projects) | Проект, к которому относится документ |
| `template_id` | UUID (FK → custom_templates) | Пользовательский шаблон, на основе которого создан deliverable |
| `title` | TEXT | Название документа |
| `status` | TEXT | Статус документа: `draft` (черновик) или `final` (финальная версия) |
| `created_at` | TIMESTAMPTZ | Время создания документа |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Ограничения:**
- `CHECK (status IN ('draft', 'final'))` - валидация статуса

**Индексы:**
- `idx_deliverables_project_id` - по полю `project_id`
- `idx_deliverables_template_id` - по полю `template_id`
- `idx_deliverables_status` - по полю `status`

**Триггеры:**
- `update_deliverables_updated_at` - автоматическое обновление `updated_at`

#### Таблица `deliverable_sections`
Секции готовых документов (Outputs) с контентом для редактора, workflow статусами и блокировками.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `deliverable_id` | UUID (FK → deliverables) | Документ, к которому относится секция |
| `custom_section_id` | UUID (FK → custom_sections) | Связь с пользовательской секцией шаблона |
| `parent_id` | UUID (FK → deliverable_sections) | Родительская секция для построения древовидной структуры (может быть NULL) |
| `content_html` | TEXT | HTML контент секции для редактора Tiptap |
| `status` | deliverable_section_status_enum | Статус секции в workflow: `empty`, `draft_ai`, `in_progress`, `review`, `approved` |
| `used_source_section_ids` | UUID[] | Массив ID секций исходных документов (source_sections), использованных для генерации |
| `locked_by_user_id` | UUID (FK → auth.users) | ID пользователя, заблокировавшего секцию для редактирования |
| `locked_at` | TIMESTAMPTZ | Время блокировки секции |
| `created_at` | TIMESTAMPTZ | Время создания секции |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Ограничения:**
- Статус должен быть одним из значений enum `deliverable_section_status_enum`

**Индексы:**
- `idx_deliverable_sections_deliverable_id` - по полю `deliverable_id`
- `idx_deliverable_sections_custom_section_id` - по полю `custom_section_id`
- `idx_deliverable_sections_parent_id` - по полю `parent_id`
- `idx_deliverable_sections_status` - по полю `status`
- `idx_deliverable_sections_locked_by` - по полю `locked_by_user_id`
- `idx_deliverable_sections_used_source_section_ids` - GIN индекс для массива UUID

**Триггеры:**
- `update_deliverable_sections_updated_at` - автоматическое обновление `updated_at`
- `deliverable_section_history_trigger` - автоматическое создание записи истории при изменении

#### Таблица `deliverable_section_history`
История изменений секций готовых документов (audit trail).

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор записи истории |
| `section_id` | UUID (FK → deliverable_sections) | Секция, для которой записана история |
| `content_snapshot` | TEXT | Снимок HTML контента на момент изменения |
| `changed_by_user_id` | UUID (FK → auth.users) | Пользователь, внесший изменение |
| `change_reason` | TEXT | Причина изменения (например, "AI generation", "Manual edit", "Review feedback") |
| `created_at` | TIMESTAMPTZ | Время создания записи истории |

**Индексы:**
- `idx_deliverable_section_history_section_id` - по полю `section_id`
- `idx_deliverable_section_history_changed_by` - по полю `changed_by_user_id`
- `idx_deliverable_section_history_created_at` - по полю `created_at` (DESC)

**Триггеры:**
- Автоматическое создание записей через триггер `deliverable_section_history_trigger` при изменении `deliverable_sections`

## Связи между таблицами (Foreign Keys)

### Иерархия организаций и пользователей
```
auth.users
  └── profiles (id → auth.users.id)
      ├── organization_members (user_id → profiles.id)
      └── project_members (user_id → profiles.id)

organizations
  ├── profiles (organization_id → organizations.id)
  ├── organization_members (organization_id → organizations.id)
  └── projects (organization_id → organizations.id)
```

### Иерархия проектов и документов
```
projects
  ├── project_members (project_id → projects.id)
  ├── source_documents (project_id → projects.id)
  ├── study_globals (project_id → projects.id)
  └── deliverables (project_id → projects.id)

source_documents
  ├── source_documents (parent_document_id → source_documents.id) [самоссылка для версионирования]
  └── source_sections (document_id → source_documents.id)
      └── study_globals (source_section_id → source_sections.id)

deliverables
  ├── custom_templates (template_id → custom_templates.id)
  └── deliverable_sections (deliverable_id → deliverables.id)
      ├── deliverable_sections (parent_id → deliverable_sections.id) [самоссылка]
      ├── custom_sections (custom_section_id → custom_sections.id)
      └── deliverable_section_history (section_id → deliverable_sections.id)
```

### Идеальные и пользовательские шаблоны
```
ideal_templates
  ├── ideal_sections (template_id → ideal_templates.id)
  └── custom_templates (base_ideal_template_id → ideal_templates.id)

ideal_sections
  ├── ideal_sections (parent_id → ideal_sections.id) [самоссылка]
  ├── ideal_mappings (target_ideal_section_id → ideal_sections.id)
  ├── ideal_mappings (source_ideal_section_id → ideal_sections.id)
  ├── custom_sections (ideal_section_id → ideal_sections.id)
  ├── custom_mappings (source_ideal_section_id → ideal_sections.id)
  └── custom_mappings (target_ideal_section_id → ideal_sections.id)

custom_templates
  ├── custom_sections (custom_template_id → custom_templates.id)
  ├── source_documents (template_id → custom_templates.id)
  └── deliverables (template_id → custom_templates.id)

custom_sections
  ├── custom_sections (parent_id → custom_sections.id) [самоссылка]
  ├── custom_mappings (target_custom_section_id → custom_sections.id)
  ├── custom_mappings (source_custom_section_id → custom_sections.id)
  ├── source_sections (custom_section_id → custom_sections.id)
  └── deliverable_sections (custom_section_id → custom_sections.id)
```

## Функции базы данных

### Функции проверки доступа

#### `is_org_admin(org_id UUID, check_user_id UUID) → BOOLEAN`
Проверяет, является ли пользователь администратором организации.

**Использование:** `SECURITY DEFINER` для обхода RLS и предотвращения рекурсии.

#### `is_org_member(org_id UUID, check_user_id UUID) → BOOLEAN`
Проверяет, является ли пользователь участником организации.

**Использование:** `SECURITY DEFINER` для обхода RLS и предотвращения рекурсии.

#### `has_project_access(proj_id UUID, check_user_id UUID) → BOOLEAN`
Проверяет, имеет ли пользователь доступ к проекту (как админ организации или как участник проекта).

**Логика:**
- Возвращает `TRUE`, если пользователь является админом организации проекта
- ИЛИ если пользователь является участником проекта

#### `is_project_owner(proj_id UUID, check_user_id UUID) → BOOLEAN`
Проверяет, является ли пользователь владельцем проекта.

**Использование:** `SECURITY DEFINER` для обхода RLS и предотвращения рекурсии.

### Функции создания сущностей

#### `create_user_organization(org_name TEXT, org_slug TEXT, creator_user_id UUID) → UUID`
Создает организацию для пользователя (обходит RLS).

**Использование:** `SECURITY DEFINER` для обхода RLS при создании первой организации.

#### `create_user_project(p_study_code TEXT, p_title TEXT, p_sponsor TEXT, p_therapeutic_area TEXT, p_status TEXT, p_organization_id UUID, p_created_by UUID) → UUID`
Создает проект для пользователя (обходит RLS).

**Использование:** `SECURITY DEFINER` для обхода RLS при создании проекта.

#### `create_source_document(p_project_id UUID, p_name TEXT, p_storage_path TEXT, p_doc_type TEXT, p_user_id UUID) → UUID`
Создает source_document с проверкой доступа (обходит проблему с auth.uid()).

**Использование:** `SECURITY DEFINER` для обхода RLS при создании документа. Проверяет доступ пользователя к проекту перед созданием документа.

#### `create_deliverable_section_history() → TRIGGER`
Автоматически создает запись истории изменений при обновлении deliverable_sections.

**Использование:** Триггерная функция, вызывается автоматически при изменении контента или статуса секции.

#### `unlock_stale_deliverable_sections(timeout_minutes INTEGER) → INTEGER`
Разблокирует секции, заблокированные более указанного количества минут (для очистки зависших блокировок).

**Параметры:**
- `timeout_minutes` - количество минут (по умолчанию 60)

**Возвращает:** Количество разблокированных секций

**Использование:** Можно запускать по расписанию для автоматической очистки зависших блокировок.

### Вспомогательные функции

#### `update_updated_at_column() → TRIGGER`
Автоматически обновляет поле `updated_at` при изменении записи.

**Применяется к таблицам:**
- `organizations`
- `profiles`
- `projects`
- `ideal_templates`
- `ideal_sections`
- `custom_templates`
- `custom_sections`
- `deliverables`
- `deliverable_sections`

## Триггеры

### Автоматическое назначение ролей

#### `auto_assign_org_admin_trigger`
**Таблица:** `organizations`  
**Событие:** `AFTER INSERT`  
**Функция:** `auto_assign_org_admin()`

Автоматически назначает создателя организации как администратора (`org_admin`) в таблице `organization_members`.

#### `auto_assign_project_owner_trigger`
**Таблица:** `projects`  
**Событие:** `AFTER INSERT`  
**Функция:** `auto_assign_project_owner()`

Автоматически назначает создателя проекта как владельца (`project_owner`) в таблице `project_members`.

### Автоматическое обновление временных меток

#### `update_organizations_updated_at`
**Таблица:** `organizations`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_profiles_updated_at`
**Таблица:** `profiles`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_projects_updated_at`
**Таблица:** `projects`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_deliverables_updated_at`
**Таблица:** `deliverables`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_ideal_templates_updated_at`
**Таблица:** `ideal_templates`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_ideal_sections_updated_at`
**Таблица:** `ideal_sections`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_custom_templates_updated_at`
**Таблица:** `custom_templates`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_custom_sections_updated_at`
**Таблица:** `custom_sections`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

#### `update_deliverable_sections_updated_at`
**Таблица:** `deliverable_sections`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

### Автоматическое создание истории изменений

#### `deliverable_section_history_trigger`
**Таблица:** `deliverable_sections`  
**Событие:** `AFTER UPDATE`  
**Функция:** `create_deliverable_section_history()`

Автоматически создает запись в `deliverable_section_history` при изменении контента или статуса секции.

## Row Level Security (RLS)

Все таблицы имеют включенный RLS для обеспечения безопасности на уровне строк.

### Политики для организаций

- **SELECT:** Пользователи видят только организации, в которых они являются участниками
- **INSERT:** Пользователи могут создавать организации (автоматически становятся админами)
- **UPDATE/DELETE:** Только админы организации могут обновлять/удалять организацию

### Политики для профилей

- **SELECT:** Пользователи видят свой профиль и профили других пользователей в своих организациях
- **INSERT:** Пользователи могут создавать только свой профиль
- **UPDATE:** Пользователи могут обновлять только свой профиль

### Политики для участников организаций

- **SELECT:** Пользователи видят участников организаций, в которых они являются участниками
- **INSERT:** Создатель организации может добавить себя как админа (для триггера)
- **UPDATE/DELETE:** Только админы организации могут управлять участниками

### Политики для проектов

- **SELECT:** Пользователи видят только проекты, к которым имеют доступ (через `has_project_access`)
- **INSERT:** Пользователи могут создавать проекты в организациях, где они являются участниками
- **UPDATE/DELETE:** Админы организации или владельцы проекта могут обновлять/удалять проект

### Политики для участников проектов

- **SELECT:** Пользователи видят участников проектов, к которым имеют доступ
- **INSERT/UPDATE/DELETE:** Админы организации или владельцы проекта могут управлять участниками

### Политики для документов

- **SELECT:** Пользователи видят документы проектов, к которым имеют доступ
- **INSERT:** Пользователи могут создавать документы в проектах, к которым имеют доступ
- **UPDATE:** Только редакторы и владельцы проекта могут обновлять документы

### Политики для секций исходных документов (source_sections)

- **SELECT:** Пользователи видят секции исходных документов проектов, к которым имеют доступ
- **INSERT/UPDATE:** Только редакторы и владельцы проекта могут создавать/обновлять секции

### Политики для готовых документов (deliverables)

- **SELECT:** Пользователи видят документы проектов, к которым имеют доступ
- **INSERT:** Пользователи могут создавать документы в проектах, к которым имеют доступ
- **UPDATE/DELETE:** Только редакторы и владельцы проекта могут обновлять/удалять документы

### Политики для секций готовых документов (deliverable_sections)

- **SELECT:** Пользователи видят секции документов проектов, к которым имеют доступ
- **INSERT/UPDATE/DELETE:** Только редакторы и владельцы проекта могут создавать/обновлять/удалять секции

### Политики для истории изменений (deliverable_section_history)

- **SELECT:** Пользователи видят историю секций документов, к которым имеют доступ
- **INSERT:** Создание записей истории возможно только через триггер (пользователи не могут напрямую вставлять записи)

### Политики для идеальных шаблонов

- **SELECT:** Все авторизованные пользователи могут читать идеальные шаблоны (`ideal_templates`, `ideal_sections`, `ideal_mappings`)
- **INSERT/UPDATE/DELETE:** Управление отключено (требуется суперадмин, в будущем можно расширить)

### Политики для пользовательских шаблонов

- **SELECT:** Пользователи видят пользовательские шаблоны своих проектов или глобальные шаблоны своих организаций (`custom_templates`, `custom_sections`, `custom_mappings`)
- **INSERT:** Пользователи могут создавать пользовательские шаблоны для своих проектов (требуется доступ к проекту)
- **UPDATE/DELETE:** Участники проекта с ролью editor или выше могут редактировать шаблоны

### Политики для глобальных переменных

- **SELECT:** Пользователи видят глобальные переменные проектов, к которым имеют доступ
- **INSERT/UPDATE:** Только редакторы и владельцы проекта могут создавать/обновлять глобальные переменные

### Политики для Supabase Storage

**ВНИМАНИЕ:** Политики для `storage.objects` требуют прав владельца схемы storage и не могут быть выполнены через обычную миграцию.

Политики доступа для bucket `documents` в Supabase Storage должны настраиваться вручную через Supabase Dashboard > Storage > Policies или через SQL Editor от имени суперадмина.

Рекомендуемые политики:
- **INSERT (загрузка):** Участники проекта могут загружать файлы в папки своих проектов (путь должен начинаться с `projects/{project_id}/`)
- **SELECT (чтение):** Участники проекта могут читать файлы из папок своих проектов
- **DELETE (удаление):** Участники проекта могут удалять файлы из папок своих проектов

**Требования:**
- Bucket `documents` должен существовать в Supabase Dashboard > Storage
- Путь к файлу должен соответствовать формату: `projects/{project_id}/{filename}`

Примеры SQL для создания политик можно найти в комментариях файла миграции.

## Индексы

### B-tree индексы
Используются для стандартных запросов по полям с условиями равенства и диапазонами.

### Векторные индексы (IVFFlat)
Используются для семантического поиска по векторным эмбеддингам:
- `source_sections.embedding`
- `ideal_sections.embedding`

**Тип:** `ivfflat` с оператором `vector_cosine_ops` для поиска по косинусному расстоянию.

**Примечание:** Индексы создаются только для записей, где `embedding IS NOT NULL`.

### GIN индексы
Используются для индексации массивов и JSONB полей:
- `deliverable_sections.used_source_section_ids` - GIN индекс для массива UUID для быстрого поиска использованных секций
- `source_sections.bbox` - GIN индекс для JSONB поля с координатами текста

## Принципы проектирования

1. **Мультитенантность:** Изоляция данных через организации с RLS
2. **Разделение Inputs/Outputs:** Четкое разделение исходных документов (source_documents, source_sections) и готовых документов (deliverables, deliverable_sections)
3. **Гибридный поиск:** Комбинация структурного поиска (по номерам секций) и семантического (по эмбеддингам)
4. **Структурный подход:** Хранение документов как иерархии секций, а не случайных чанков
5. **Глобальный контекст:** Извлечение и хранение ключевых фактов исследования для использования в генерации
6. **Двухуровневая система шаблонов:**
   - **Идеальные шаблоны (System Master Data):** Золотые стандарты, доступные всем пользователям
   - **Пользовательские шаблоны (Configuration):** Настройки на основе идеальных шаблонов для конкретных проектов или организаций
7. **Версионирование:** Поддержка версий документов через `parent_document_id` и `version_label` в source_documents
8. **Workflow:** Workflow для секций готовых документов (empty → generated → reviewed)
9. **Блокировки:** Механизм блокировки секций для предотвращения одновременного редактирования (`locked_by_user_id`, `locked_at`)
10. **Audit Trail:** 
    - Отслеживание использованных исходных секций через массив `used_source_section_ids` в deliverable_sections
    - Полная история изменений через таблицу `deliverable_section_history`
11. **Безопасность:** RLS на всех таблицах для обеспечения изоляции данных
12. **Координаты текста:** Хранение координат (bbox) для подсветки исходных секций в PDF-документах

## Миграции

Схема базы данных определена в файлах:
- `docs/schema.sql` - полная схема с расширениями, функциями, триггерами и политиками
- `schema_organizations_profiles_projects.sql` - миграция для организаций, профилей и проектов

При изменении схемы необходимо:
1. Обновить SQL файлы миграций
2. Обновить этот документ
3. Протестировать RLS политики
4. Обновить документацию по API (если изменились доступные поля)

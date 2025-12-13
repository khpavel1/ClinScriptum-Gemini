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
| `status` | TEXT | Статус: `draft`, `active`, `archived` |
| `therapeutic_area` | TEXT | Терапевтическая область |
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
Метаданные исходных документов (Protocol, SAP, CSR и т.д.).

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор документа |
| `project_id` | UUID (FK → projects) | Идентификатор проекта |
| `name` | TEXT | Название документа |
| `storage_path` | TEXT | Путь к файлу в Supabase Storage |
| `doc_type` | TEXT | Тип документа (Protocol, SAP, CSR и т.д.) |
| `status` | TEXT | Статус обработки: `uploading`, `indexed`, `error` |
| `parsing_metadata` | JSONB | Технические метаданные парсинга (время, количество страниц, ошибки) |
| `parsing_quality_score` | INTEGER | Ручная оценка качества парсинга (1-5) |
| `parsing_quality_comment` | TEXT | Комментарий к оценке качества |
| `detected_tables_count` | INTEGER | Количество таблиц, обнаруженных парсером |
| `created_at` | TIMESTAMPTZ | Время загрузки документа |

**Индексы:**
- `idx_source_documents_project_id` - по полю `project_id`
- `idx_source_documents_status` - по полю `status`
- `idx_source_documents_doc_type` - по полю `doc_type`

#### Таблица `source_sections`
Секции исходных документов (Inputs) с классификацией по каноническим секциям.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `document_id` | UUID (FK → source_documents) | Идентификатор документа |
| `section_number` | TEXT | Номер секции (например, "3.1.2") |
| `header` | TEXT | Заголовок секции |
| `page_number` | INTEGER | Номер страницы |
| `content_text` | TEXT | Чистый текст для поиска |
| `content_markdown` | TEXT | Текст с разметкой таблиц (для LLM) |
| `embedding` | vector(1536) | Векторное представление секции для семантического поиска |
| `canonical_code` | TEXT (FK → canonical_sections) | Ссылка на каноническую секцию |
| `classification_confidence` | FLOAT | Уверенность автоматической классификации (0.0-1.0) |
| `template_section_id` | UUID (FK → template_sections) | Связь с идеальным прототипом секции из шаблона |
| `created_at` | TIMESTAMPTZ | Время создания секции |

**Индексы:**
- `idx_source_sections_document_id` - по полю `document_id`
- `idx_source_sections_canonical_code` - по полю `canonical_code`
- `idx_source_sections_template_section_id` - по полю `template_section_id`
- `idx_source_sections_embedding` - векторный индекс (IVFFlat) для семантического поиска

### 4. Справочники и таксономия

#### Таблица `canonical_sections`
Справочник канонических секций документов (таксономия).

| Поле | Тип | Описание |
|------|-----|----------|
| `code` | TEXT (PK) | Уникальный код секции (например, "INCLUSION_CRITERIA") |
| `name` | TEXT | Название секции |
| `description` | TEXT | Описание секции |
| `created_at` | TIMESTAMPTZ | Время создания записи |

#### Таблица `canonical_anchors`
Справочник якорей для классификации секций документов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор |
| `canonical_code` | TEXT (FK → canonical_sections) | Ссылка на каноническую секцию |
| `anchor_text` | TEXT | Текст-якорь для сопоставления с секциями документов |
| `embedding` | vector(1536) | Векторное представление якоря для семантического поиска |
| `created_at` | TIMESTAMPTZ | Время создания записи |

**Индексы:**
- `idx_canonical_anchors_code` - по полю `canonical_code`
- `idx_canonical_anchors_embedding` - векторный индекс (IVFFlat) для семантического поиска

### 5. Граф шаблонов (Template Graph)

#### Таблица `doc_templates`
Типы документов (шаблоны) - золотые стандарты структур.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор шаблона |
| `name` | TEXT (UNIQUE) | Уникальное имя шаблона (например, "Protocol_EAEU", "CSR_ICH_E3") |
| `description` | TEXT | Описание назначения шаблона |
| `created_at` | TIMESTAMPTZ | Время создания шаблона |

**Индексы:**
- `idx_doc_templates_name` - по полю `name`

#### Таблица `template_sections`
Узлы графа шаблонов - структура секций документа.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции шаблона |
| `template_id` | UUID (FK → doc_templates) | Идентификатор шаблона |
| `parent_id` | UUID (FK → template_sections) | Родительская секция для построения древовидной структуры |
| `section_number` | TEXT | Номер секции в шаблоне (например, "3.1") |
| `title` | TEXT | Название секции |
| `description` | TEXT | Инструкция для AI о содержании секции |
| `is_mandatory` | BOOLEAN | Обязательная ли секция в шаблоне |
| `embedding` | vector(1536) | Векторное представление секции для семантического поиска при парсинге |
| `created_at` | TIMESTAMPTZ | Время создания секции |

**Индексы:**
- `idx_template_sections_template_id` - по полю `template_id`
- `idx_template_sections_parent_id` - по полю `parent_id`
- `idx_template_sections_embedding` - векторный индекс (IVFFlat) для семантического поиска

#### Таблица `section_mappings`
Ребра графа шаблонов - правила переноса данных между секциями.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор маппинга |
| `source_section_id` | UUID (FK → template_sections) | Исходная секция шаблона |
| `target_section_id` | UUID (FK → template_sections) | Целевая секция шаблона |
| `relationship_type` | TEXT | Тип связи: `direct_copy`, `summary`, `transformation`, `consistency_check` |
| `instruction` | TEXT | Промпт для AI при трансформации данных между секциями |
| `created_at` | TIMESTAMPTZ | Время создания маппинга |

**Ограничения:**
- `CHECK (source_section_id != target_section_id)` - предотвращение петель
- `CHECK (relationship_type IN ('direct_copy', 'summary', 'transformation', 'consistency_check'))` - валидация типа связи

**Индексы:**
- `idx_section_mappings_source` - по полю `source_section_id`
- `idx_section_mappings_target` - по полю `target_section_id`
- `idx_section_mappings_type` - по полю `relationship_type`

### 6. Глобальный контекст исследования

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

### 7. Готовые документы (Deliverables / Outputs)

#### Таблица `deliverables`
Готовые документы (Outputs/Deliverables), созданные на основе шаблонов.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор документа |
| `project_id` | UUID (FK → projects) | Проект, к которому относится документ |
| `template_id` | UUID (FK → doc_templates) | Шаблон документа, по которому создан deliverable (например, CSR) |
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
Секции готовых документов (Outputs) с контентом для редактора.

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID (PK) | Уникальный идентификатор секции |
| `deliverable_id` | UUID (FK → deliverables) | Документ, к которому относится секция |
| `template_section_id` | UUID (FK → template_sections) | Связь с секцией шаблона (золотой стандарт) |
| `content_html` | TEXT | HTML контент секции для редактора Tiptap |
| `status` | TEXT | Статус секции: `empty` (пустая), `generated` (сгенерирована AI), `reviewed` (проверена) |
| `used_source_section_ids` | UUID[] | Массив ID секций исходных документов (source_sections), использованных для генерации |
| `created_at` | TIMESTAMPTZ | Время создания секции |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления |

**Ограничения:**
- `CHECK (status IN ('empty', 'generated', 'reviewed'))` - валидация статуса

**Индексы:**
- `idx_deliverable_sections_deliverable_id` - по полю `deliverable_id`
- `idx_deliverable_sections_template_section_id` - по полю `template_section_id`
- `idx_deliverable_sections_status` - по полю `status`
- `idx_deliverable_sections_used_source_section_ids` - GIN индекс для массива UUID

**Триггеры:**
- `update_deliverable_sections_updated_at` - автоматическое обновление `updated_at`

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
  └── source_sections (document_id → source_documents.id)
      └── study_globals (source_section_id → source_sections.id)

deliverables
  └── deliverable_sections (deliverable_id → deliverables.id)
```

### Справочники и классификация
```
canonical_sections
  └── canonical_anchors (canonical_code → canonical_sections.code)

canonical_sections
  └── source_sections (canonical_code → canonical_sections.code)
```

### Граф шаблонов
```
doc_templates
  ├── template_sections (template_id → doc_templates.id)
  └── deliverables (template_id → doc_templates.id)

template_sections
  ├── template_sections (parent_id → template_sections.id) [самоссылка]
  ├── section_mappings (source_section_id → template_sections.id)
  ├── section_mappings (target_section_id → template_sections.id)
  ├── source_sections (template_section_id → template_sections.id)
  └── deliverable_sections (template_section_id → template_sections.id)
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

#### `create_user_project(p_study_code TEXT, p_title TEXT, p_sponsor TEXT, p_status TEXT, p_organization_id UUID, p_created_by UUID) → UUID`
Создает проект для пользователя (обходит RLS).

**Использование:** `SECURITY DEFINER` для обхода RLS при создании проекта.

### Вспомогательные функции

#### `update_updated_at_column() → TRIGGER`
Автоматически обновляет поле `updated_at` при изменении записи.

**Применяется к таблицам:**
- `organizations`
- `profiles`
- `projects`
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

#### `update_deliverable_sections_updated_at`
**Таблица:** `deliverable_sections`  
**Событие:** `BEFORE UPDATE`  
**Функция:** `update_updated_at_column()`

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

### Политики для справочников

- **SELECT:** Все авторизованные пользователи могут читать справочники (`canonical_sections`, `canonical_anchors`, `doc_templates`, `template_sections`, `section_mappings`)
- **INSERT/UPDATE/DELETE:** Управление справочниками отключено (требуется суперадмин, в будущем можно расширить)

### Политики для глобальных переменных

- **SELECT:** Пользователи видят глобальные переменные проектов, к которым имеют доступ
- **INSERT/UPDATE:** Только редакторы и владельцы проекта могут создавать/обновлять глобальные переменные

## Индексы

### B-tree индексы
Используются для стандартных запросов по полям с условиями равенства и диапазонами.

### Векторные индексы (IVFFlat)
Используются для семантического поиска по векторным эмбеддингам:
- `source_sections.embedding`
- `canonical_anchors.embedding`
- `template_sections.embedding`

**Тип:** `ivfflat` с оператором `vector_cosine_ops` для поиска по косинусному расстоянию.

### GIN индексы
Используются для индексации массивов:
- `deliverable_sections.used_source_section_ids` - GIN индекс для массива UUID для быстрого поиска использованных секций

## Принципы проектирования

1. **Мультитенантность:** Изоляция данных через организации с RLS
2. **Разделение Inputs/Outputs:** Четкое разделение исходных документов (source_documents, source_sections) и готовых документов (deliverables, deliverable_sections)
3. **Гибридный поиск:** Комбинация структурного поиска (по номерам секций) и семантического (по эмбеддингам)
4. **Структурный подход:** Хранение документов как иерархии секций, а не случайных чанков
5. **Глобальный контекст:** Извлечение и хранение ключевых фактов исследования для использования в генерации
6. **Граф шаблонов:** Моделирование правил переноса данных между типами документов
7. **Audit Trail:** Отслеживание использованных исходных секций через массив `used_source_section_ids` в deliverable_sections
8. **Безопасность:** RLS на всех таблицах для обеспечения изоляции данных

## Миграции

Схема базы данных определена в файлах:
- `docs/schema.sql` - полная схема с расширениями, функциями, триггерами и политиками
- `schema_organizations_profiles_projects.sql` - миграция для организаций, профилей и проектов

При изменении схемы необходимо:
1. Обновить SQL файлы миграций
2. Обновить этот документ
3. Протестировать RLS политики
4. Обновить документацию по API (если изменились доступные поля)

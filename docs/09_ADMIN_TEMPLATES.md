# 09. Ideal Template Manager (Админ-панель)

## Обзор

Ideal Template Manager — это административный интерфейс для управления идеальными шаблонами (золотыми стандартами структур документов). Позволяет создавать, редактировать и настраивать структуры шаблонов с поддержкой иерархических секций и правил маппинга между шаблонами.

## Архитектура

### Компоненты

1. **Server Actions** (`app/admin/templates/actions.ts`)
   - Все операции с базой данных через Next.js Server Actions
   - Работа с таблицами: `ideal_templates`, `ideal_sections`, `ideal_mappings`

2. **Zustand Store** (`lib/stores/admin-template-store.ts`)
   - Управление состоянием дерева секций в памяти
   - Оптимистичные обновления UI
   - Кэширование маппингов

3. **UI Компоненты**
   - `page.tsx` — главный компонент с тремя панелями
   - `TemplatesSidebar` — список шаблонов
   - `StructureTree` — дерево секций с возможностью редактирования
   - `SectionInspector` — детальный просмотр и редактирование секции

## Функциональность

### 1. Управление шаблонами

#### Создание шаблона
- **Поля:** название, версия (число), статус (Active/Draft)
- **Валидация:** уникальность комбинации (name, version)
- **Server Action:** `createTemplate()`

#### Просмотр списка шаблонов
- Отображение всех шаблонов с фильтрацией по поисковому запросу
- Индикация статуса (Active/Draft)
- Выбор шаблона для редактирования
- **Server Action:** `getTemplates()`

### 2. Управление структурой секций

#### Создание секции
- **Поля:** название (title)
- **Логика `order_index`:**
  - При создании секции автоматически определяется максимальный `order_index` среди siblings (секций с тем же `parent_id`)
  - Новая секция получает `order_index = max + 1` (добавляется в конец списка)
- **Родительская секция:** можно указать родителя при создании (или создать на корневом уровне)
- **Server Action:** `createSection()`

#### Построение дерева
- Секции хранятся в БД как плоский список с `parent_id` (adjacency list)
- При загрузке структуры шаблона выполняется построение дерева:
  - Рекурсивное построение иерархии на основе `parent_id`
  - Автоматический расчет номеров секций (1, 1.1, 1.2.1 и т.д.)
  - Сортировка по `order_index` на каждом уровне
- **Server Action:** `getTemplateStructure()`

#### Редактирование секции
- Обновление названия секции
- **Server Action:** `updateSection()`

#### Удаление секции
- **Валидация:** нельзя удалить секцию, у которой есть дочерние элементы
- **Server Action:** `deleteSection()`

### 3. Перемещение секций

#### Move Up / Move Down
- Обмен `order_index` с соседней секцией (предыдущей или следующей)
- Простая логика: swap `order_index` между текущей и соседней секцией
- **Server Action:** `reorderSection(action: 'moveUp' | 'moveDown')`

#### Indent (Увеличение отступа)
- Делает секцию дочерней для предыдущего sibling
- **Логика:**
  1. Находит предыдущий sibling
  2. Определяет максимальный `order_index` среди детей этого sibling
  3. Устанавливает `parent_id = previousSibling.id` и `order_index = maxChildOrder + 1`
  4. Сдвигает `order_index` всех последующих siblings на -1
- **Server Action:** `reorderSection(action: 'indent')`

#### Outdent (Уменьшение отступа)
- Делает секцию sibling своего родителя
- **Логика:**
  1. Получает родительскую секцию
  2. Находит siblings родителя
  3. Размещает секцию после родителя (устанавливает `parent_id = parent.parent_id` и `order_index = parent.order_index + 1`)
  4. Сдвигает `order_index` всех последующих siblings родителя на +1
- **Server Action:** `reorderSection(action: 'outdent')`

### 4. Управление маппингами

#### Создание маппинга
- **Поля:**
  - `target_ideal_section_id` — целевая секция (текущая выбранная)
  - `source_ideal_section_id` — исходная секция из другого шаблона
  - `instruction` — промпт для AI при трансформации данных
- **Поиск исходных секций:**
  - Поиск секций из всех других шаблонов (исключая текущий)
  - Отображение с указанием шаблона: `[Template Name] Section Title`
- **Логика `order_index`:**
  - При создании маппинга определяется максимальный `order_index` среди маппингов для целевой секции
  - Новый маппинг получает `order_index = max + 1`
- **Server Action:** `saveMapping()`

#### Просмотр маппингов
- Отображение всех маппингов для выбранной секции
- Показ информации: шаблон-источник, секция-источник, инструкция, порядок
- **Server Action:** `getTemplateStructure()` (включает обогащенные данные о маппингах)

#### Обновление маппинга
- Изменение `source_ideal_section_id` и `instruction`
- Обновление `order_index` (если указано)
- **Server Action:** `saveMapping()` (с указанием `id` для обновления)

## Технические детали

### Server Actions

Все Server Actions находятся в `app/admin/templates/actions.ts`:

```typescript
// Получение данных
getTemplates(): Promise<{ data: IdealTemplate[] | null; error: string | null }>
getTemplateStructure(templateId: string): Promise<{ data: { tree: TreeNode[]; mappings: IdealMapping[] } | null; error: string | null }>
searchSections(templateId: string, query?: string): Promise<{ data: IdealSection[] | null; error: string | null }>

// Создание
createTemplate(data: { name: string; version: number; isActive?: boolean }): Promise<{ data: IdealTemplate | null; error: string | null }>
createSection(data: { templateId: string; parentId?: string | null; title: string }): Promise<{ data: IdealSection | null; error: string | null }>
saveMapping(data: { id?: string; targetSectionId: string; sourceSectionId: string; instruction: string; orderIndex?: number }): Promise<{ data: IdealMapping | null; error: string | null }>

// Обновление
updateSection(id: string, data: { title?: string }): Promise<{ data: IdealSection | null; error: string | null }>

// Удаление
deleteSection(id: string): Promise<{ success: boolean; error: string | null }>

// Перемещение
reorderSection(id: string, action: 'moveUp' | 'moveDown' | 'indent' | 'outdent'): Promise<{ success: boolean; error: string | null }>
```

### Zustand Store

Store находится в `lib/stores/admin-template-store.ts`:

```typescript
interface AdminTemplateStore {
  // State
  templates: Template[]
  selectedTemplateId: string | null
  tree: TreeNode | null
  selectedNodeId: string | null
  mappings: Record<string, Mapping[]>

  // Actions
  setTemplates(templates: Template[]): void
  selectTemplate(templateId: string): void
  setTree(tree: TreeNode | null): void
  selectNode(nodeId: string | null): void
  addNode(node: TreeNode, parentId?: string | null): void
  updateNode(nodeId: string, updates: Partial<TreeNode>): void
  removeNode(nodeId: string): void
  setMappings(sectionId: string, mappings: Mapping[]): void
  addMapping(sectionId: string, mapping: Mapping): void
  removeMapping(sectionId: string, mappingId: string): void

  // Helpers
  findNode(nodeId: string, root?: TreeNode): TreeNode | null
  updateNodeInTree(nodeId: string, updates: Partial<TreeNode>, root?: TreeNode): TreeNode | null
}
```

### Построение дерева из плоского списка

Алгоритм построения дерева (функция `buildTree` в `actions.ts`):

1. **Первый проход:** создание Map всех узлов
2. **Второй проход:** построение иерархии и расчет номеров
   - Для корневых секций: номер = индекс среди корневых siblings + 1
   - Для дочерних: номер = `parent.number + '.' + (индекс среди siblings + 1)`
3. **Сортировка:** рекурсивная сортировка детей по `order_index`

### Обогащение маппингов

При загрузке структуры шаблона маппинги обогащаются информацией о source sections и templates:

1. Получение всех `source_ideal_section_id` из маппингов
2. Загрузка source sections из БД
3. Загрузка templates для source sections
4. Добавление полей `_sourceSectionTitle` и `_sourceTemplateName` к маппингам

## UI Компоненты

### Главная страница (`app/admin/templates/page.tsx`)

Три панели с возможностью изменения размера:

1. **Левая панель:** Список шаблонов (`TemplatesSidebar`)
   - Поиск по названию
   - Создание нового шаблона
   - Выбор шаблона для редактирования

2. **Центральная панель:** Дерево структуры (`StructureTree`)
   - Визуализация иерархии секций
   - Выбор секции
   - Создание новой секции
   - Контекстное меню: Move Up/Down, Indent/Outdent, Delete

3. **Правая панель:** Инспектор секции (`SectionInspector`)
   - Детальная информация о секции
   - Редактирование названия
   - Вкладка "General": основные свойства
   - Вкладка "AI Mappings": список маппингов и создание новых

### Диалоги

1. **Создание шаблона:**
   - Название, версия, статус

2. **Создание секции:**
   - Название секции
   - Родитель определяется автоматически (выбранная секция или корень)

3. **Создание маппинга:**
   - Выбор source section из других шаблонов
   - Ввод инструкции для AI

## Безопасность

- Все Server Actions проверяют аутентификацию пользователя
- RLS политики в БД обеспечивают доступ только авторизованным пользователям
- Идеальные шаблоны доступны для чтения всем авторизованным пользователям
- Управление (INSERT/UPDATE/DELETE) требует прав администратора (в будущем)

## Ограничения и будущие улучшения

### Текущие ограничения

1. **Поля секций:**
   - В БД нет полей `description` и `isMandatory` (используются только в UI)
   - Эти поля можно добавить в будущем при необходимости

2. **Версионирование шаблонов:**
   - Поле `group_id` существует, но логика группировки версий не реализована

3. **Drag & Drop:**
   - UI поддерживает drag & drop, но логика перемещения через drag & drop не реализована
   - Используются кнопки Move Up/Down и Indent/Outdent

### Планируемые улучшения

1. Добавление полей `description` и `isMandatory` в таблицу `ideal_sections`
2. Реализация drag & drop для перемещения секций
3. Редактирование `order_index` маппингов
4. Удаление маппингов
5. Копирование секций между шаблонами
6. Экспорт/импорт структуры шаблона

## Связанные документы

- [08_DATABASE_SCHEMA.md](./08_DATABASE_SCHEMA.md) — описание структуры БД для идеальных шаблонов
- [04_AI_ENGINE.md](./04_AI_ENGINE.md) — использование маппингов в AI Engine для генерации контента

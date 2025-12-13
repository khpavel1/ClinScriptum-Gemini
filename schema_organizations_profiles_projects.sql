-- ============================================
-- SQL Schema для Organizations, Profiles и Projects
-- На основе docs/00_MASTER_ARCH.md и docs/01_AUTH_PROJECTS.md
-- Multi-tenant архитектура с RLS для Supabase
-- ============================================

-- ============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================
-- Примечание: auth.uid() уже существует в Supabase и доступна автоматически
-- Не пытаемся создавать или изменять функции в схеме auth (permission denied)

-- ============================================
-- МИГРАЦИЯ: Удаление старых политик и функций
-- ============================================
-- Сначала удаляем все политики, которые зависят от старых функций
-- Organizations
DROP POLICY IF EXISTS "Org admins can update their organizations" ON organizations;
DROP POLICY IF EXISTS "Org admins can delete their organizations" ON organizations;
DROP POLICY IF EXISTS "Users can view their organizations" ON organizations;
DROP POLICY IF EXISTS "Users can create organizations" ON organizations;

-- Profiles
DROP POLICY IF EXISTS "Users can view profiles in their organizations" ON profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can create their own profile" ON profiles;

-- Organization Members
DROP POLICY IF EXISTS "Org admins can manage members" ON organization_members;
DROP POLICY IF EXISTS "Users can view members of their organizations" ON organization_members;
DROP POLICY IF EXISTS "Organization creators can add themselves" ON organization_members;

-- Projects
DROP POLICY IF EXISTS "Project owners and org admins can update projects" ON projects;
DROP POLICY IF EXISTS "Project owners and org admins can delete projects" ON projects;
DROP POLICY IF EXISTS "Users can create projects in their organizations" ON projects;
DROP POLICY IF EXISTS "Users can view accessible projects" ON projects;

-- Project Members
DROP POLICY IF EXISTS "Project owners and org admins can manage project members" ON project_members;
DROP POLICY IF EXISTS "Users can view members of accessible projects" ON project_members;

-- Source Documents
DROP POLICY IF EXISTS "Project members can view documents" ON source_documents;
DROP POLICY IF EXISTS "Project members can create documents" ON source_documents;
DROP POLICY IF EXISTS "Project editors can update documents" ON source_documents;

-- Document Sections
-- Политики для document_sections удаляются в разделе миграции ниже
-- (после проверки существования таблицы)

-- Study Globals
DROP POLICY IF EXISTS "Project members can view study globals" ON study_globals;
DROP POLICY IF EXISTS "Project editors can create study globals" ON study_globals;
DROP POLICY IF EXISTS "Project editors can update study globals" ON study_globals;

-- Теперь удаляем старые функции (CASCADE для автоматического удаления зависимостей, если что-то пропустили)
DROP FUNCTION IF EXISTS is_org_admin(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS is_org_member(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS has_project_access(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS is_project_owner(UUID, UUID) CASCADE;

-- Вспомогательная функция: проверка, является ли пользователь админом организации
CREATE OR REPLACE FUNCTION is_org_admin(org_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND organization_members.user_id = check_user_id
          AND role = 'org_admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION is_org_admin IS 'Проверяет, является ли пользователь администратором организации';

-- Вспомогательная функция: проверка доступа к проекту
-- Пользователь имеет доступ, если он админ организации ИЛИ участник проекта
CREATE OR REPLACE FUNCTION has_project_access(proj_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    org_id UUID;
BEGIN
    -- Получаем organization_id проекта
    SELECT organization_id INTO org_id FROM projects WHERE id = proj_id;
    
    IF org_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Проверяем доступ: либо админ организации, либо участник проекта
    RETURN (
        is_org_admin(org_id, check_user_id) OR
        EXISTS (
            SELECT 1 FROM project_members
            WHERE project_id = proj_id
              AND project_members.user_id = check_user_id
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION has_project_access IS 'Проверяет, имеет ли пользователь доступ к проекту (как админ организации или как участник проекта)';

-- Вспомогательная функция: проверка, является ли пользователь владельцем проекта
-- Использует SECURITY DEFINER для обхода RLS и предотвращения рекурсии
CREATE OR REPLACE FUNCTION is_project_owner(proj_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM project_members
        WHERE project_id = proj_id
          AND project_members.user_id = check_user_id
          AND role = 'project_owner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION is_project_owner IS 'Проверяет, является ли пользователь владельцем проекта (обходит RLS для предотвращения рекурсии)';

-- Вспомогательная функция: проверка членства в организации
-- Использует SECURITY DEFINER для обхода RLS и предотвращения рекурсии
CREATE OR REPLACE FUNCTION is_org_member(org_id UUID, check_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND organization_members.user_id = check_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION is_org_member IS 'Проверяет, является ли пользователь участником организации (обходит RLS для предотвращения рекурсии)';

-- Функция для создания организации пользователем
-- Использует SECURITY DEFINER для обхода RLS при создании первой организации
CREATE OR REPLACE FUNCTION create_user_organization(
    org_name TEXT,
    org_slug TEXT,
    creator_user_id UUID
)
RETURNS UUID AS $$
DECLARE
    new_org_id UUID;
BEGIN
    -- Создаем организацию
    INSERT INTO organizations (name, slug, created_by)
    VALUES (org_name, org_slug, creator_user_id)
    RETURNING id INTO new_org_id;
    
    -- Триггер auto_assign_org_admin_trigger автоматически добавит создателя как админа
    -- Но мы также можем обновить профиль пользователя, если нужно
    
    RETURN new_org_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_user_organization IS 'Создает организацию для пользователя (обходит RLS)';

-- Функция для создания проекта пользователем
-- Использует SECURITY DEFINER для обхода RLS при создании проекта
CREATE OR REPLACE FUNCTION create_user_project(
    p_study_code TEXT,
    p_title TEXT,
    p_sponsor TEXT,
    p_status TEXT,
    p_organization_id UUID,
    p_created_by UUID
)
RETURNS UUID AS $$
DECLARE
    new_project_id UUID;
BEGIN
    -- Создаем проект
    INSERT INTO projects (
        study_code,
        title,
        sponsor,
        status,
        organization_id,
        created_by
    )
    VALUES (
        p_study_code,
        p_title,
        p_sponsor,
        p_status,
        p_organization_id,
        p_created_by
    )
    RETURNING id INTO new_project_id;
    
    -- Триггер auto_assign_project_owner_trigger автоматически добавит создателя как project_owner
    
    RETURN new_project_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_user_project IS 'Создает проект для пользователя (обходит RLS)';

-- Функция для создания source_document с явной передачей user_id
-- Обходит проблему с auth.uid() возвращающим null в некоторых контекстах
CREATE OR REPLACE FUNCTION create_source_document(
    p_project_id UUID,
    p_name TEXT,
    p_storage_path TEXT,
    p_doc_type TEXT,
    p_user_id UUID
)
RETURNS UUID AS $$
DECLARE
    new_document_id UUID;
BEGIN
    -- Проверяем доступ пользователя к проекту
    IF NOT has_project_access(p_project_id, p_user_id) THEN
        RAISE EXCEPTION 'User does not have access to this project';
    END IF;
    
    -- Создаем документ
    INSERT INTO source_documents (
        project_id,
        name,
        storage_path,
        doc_type,
        status
    )
    VALUES (
        p_project_id,
        p_name,
        p_storage_path,
        p_doc_type,
        'uploading'
    )
    RETURNING id INTO new_document_id;
    
    RETURN new_document_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_source_document IS 'Создает source_document с проверкой доступа (обходит проблему с auth.uid())';

-- Предоставляем права на выполнение функции авторизованным пользователям
GRANT EXECUTE ON FUNCTION create_source_document(UUID, TEXT, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_source_document(UUID, TEXT, TEXT, TEXT, UUID) TO anon;

-- ============================================
-- 1. ORGANIZATIONS (Multi-tenant изоляция данных)
-- ============================================
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_organizations_slug ON organizations(slug);
CREATE INDEX IF NOT EXISTS idx_organizations_created_by ON organizations(created_by);

COMMENT ON TABLE organizations IS 'Мультитенантные организации для изоляции данных';
COMMENT ON COLUMN organizations.slug IS 'Уникальный идентификатор организации (URL-friendly)';
COMMENT ON COLUMN organizations.created_by IS 'Пользователь, создавший организацию (автоматически становится админом)';

-- ============================================
-- 2. PROFILES (Расширение auth.users)
-- ============================================
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_organization_id ON profiles(organization_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

COMMENT ON TABLE profiles IS 'Профили пользователей, расширение таблицы auth.users';
COMMENT ON COLUMN profiles.organization_id IS 'Основная организация пользователя (может быть NULL, т.к. пользователь может быть в нескольких организациях через organization_members)';

-- ============================================
-- 3. ORGANIZATION MEMBERS (Связь пользователей с организациями и ролями)
-- ============================================
CREATE TABLE IF NOT EXISTS organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('org_admin', 'member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_members_org_id ON organization_members(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user_id ON organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_org_members_role ON organization_members(organization_id, role);

COMMENT ON TABLE organization_members IS 'Участники организаций с ролями (org_admin, member)';
COMMENT ON COLUMN organization_members.role IS 'Роль в организации: org_admin (управляет пользователями) или member';

-- ============================================
-- 4. PROJECTS (Исследования/Проекты)
-- ============================================
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    study_code TEXT NOT NULL,
    title TEXT NOT NULL,
    sponsor TEXT,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, study_code)
);

CREATE INDEX IF NOT EXISTS idx_projects_organization_id ON projects(organization_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_study_code ON projects(study_code);
CREATE INDEX IF NOT EXISTS idx_projects_created_by ON projects(created_by);

COMMENT ON TABLE projects IS 'Исследования/проекты, привязанные к организациям';
COMMENT ON COLUMN projects.study_code IS 'Уникальный код исследования в рамках организации';
COMMENT ON COLUMN projects.status IS 'Статус проекта: draft (черновик), active (активный), archived (архив)';
COMMENT ON COLUMN projects.sponsor IS 'Спонсор исследования';

-- ============================================
-- 5. PROJECT MEMBERS (Участники проектов с ролями)
-- ============================================
CREATE TABLE IF NOT EXISTS project_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('project_owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_project_members_project_id ON project_members(project_id);
CREATE INDEX IF NOT EXISTS idx_project_members_user_id ON project_members(user_id);
CREATE INDEX IF NOT EXISTS idx_project_members_role ON project_members(project_id, role);

COMMENT ON TABLE project_members IS 'Участники проектов с ролями (project_owner, editor, viewer)';
COMMENT ON COLUMN project_members.role IS 'Роль в проекте: project_owner (полный доступ), editor (редактирование), viewer (только чтение)';

-- ============================================
-- ТРИГГЕРЫ
-- ============================================

-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггеры для updated_at
DROP TRIGGER IF EXISTS update_organizations_updated_at ON organizations;
CREATE TRIGGER update_organizations_updated_at 
    BEFORE UPDATE ON organizations
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at 
    BEFORE UPDATE ON profiles
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
CREATE TRIGGER update_projects_updated_at 
    BEFORE UPDATE ON projects
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Автоматическое назначение создателя организации как админа
-- (На основе требования из docs/01_AUTH_PROJECTS.md)
-- Используем SECURITY DEFINER для обхода RLS при создании первой записи
CREATE OR REPLACE FUNCTION auto_assign_org_admin()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.created_by IS NOT NULL THEN
        INSERT INTO organization_members (organization_id, user_id, role)
        VALUES (NEW.id, NEW.created_by, 'org_admin')
        ON CONFLICT (organization_id, user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_assign_org_admin_trigger ON organizations;
CREATE TRIGGER auto_assign_org_admin_trigger
    AFTER INSERT ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION auto_assign_org_admin();

-- Автоматическое назначение создателя проекта как project_owner
-- Используем SECURITY DEFINER для обхода RLS
CREATE OR REPLACE FUNCTION auto_assign_project_owner()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO project_members (project_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'project_owner')
    ON CONFLICT (project_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_assign_project_owner_trigger ON projects;
CREATE TRIGGER auto_assign_project_owner_trigger
    AFTER INSERT ON projects
    FOR EACH ROW
    EXECUTE FUNCTION auto_assign_project_owner();

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Включение RLS для всех таблиц
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_members ENABLE ROW LEVEL SECURITY;

-- ============================================
-- ORGANIZATIONS RLS POLICIES
-- ============================================

-- Пользователь видит только организации, в которых он является участником
-- Используем функцию is_org_member для предотвращения рекурсии
DROP POLICY IF EXISTS "Users can view their organizations" ON organizations;
CREATE POLICY "Users can view their organizations"
    ON organizations FOR SELECT
    USING (is_org_member(id, auth.uid()));

-- Пользователь может создать организацию (он автоматически становится админом через триггер)
DROP POLICY IF EXISTS "Users can create organizations" ON organizations;
CREATE POLICY "Users can create organizations"
    ON organizations FOR INSERT
    WITH CHECK (created_by = auth.uid());

-- Только админы организации могут обновлять организацию
DROP POLICY IF EXISTS "Org admins can update their organizations" ON organizations;
CREATE POLICY "Org admins can update their organizations"
    ON organizations FOR UPDATE
    USING (is_org_admin(id, auth.uid()));

-- Только админы организации могут удалять организацию
DROP POLICY IF EXISTS "Org admins can delete their organizations" ON organizations;
CREATE POLICY "Org admins can delete their organizations"
    ON organizations FOR DELETE
    USING (is_org_admin(id, auth.uid()));

-- ============================================
-- PROFILES RLS POLICIES
-- ============================================

-- Пользователь видит свой профиль
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT
    USING (id = auth.uid());

-- Пользователь видит профили других пользователей в своих организациях
-- Используем функцию is_org_member для предотвращения рекурсии
DROP POLICY IF EXISTS "Users can view profiles in their organizations" ON profiles;
CREATE POLICY "Users can view profiles in their organizations"
    ON profiles FOR SELECT
    USING (
        profiles.organization_id IS NOT NULL AND
        is_org_member(profiles.organization_id, auth.uid())
    );

-- Пользователь может обновлять свой профиль
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE
    USING (id = auth.uid());

-- Пользователь может создавать свой профиль (при регистрации)
DROP POLICY IF EXISTS "Users can create their own profile" ON profiles;
CREATE POLICY "Users can create their own profile"
    ON profiles FOR INSERT
    WITH CHECK (id = auth.uid());

-- ============================================
-- ORGANIZATION MEMBERS RLS POLICIES
-- ============================================

-- Пользователь видит участников организаций, в которых он является участником
-- Используем функцию is_org_member для предотвращения рекурсии
DROP POLICY IF EXISTS "Users can view members of their organizations" ON organization_members;
CREATE POLICY "Users can view members of their organizations"
    ON organization_members FOR SELECT
    USING (is_org_member(organization_id, auth.uid()));

-- Создатель организации может добавить себя как админа (для триггера)
DROP POLICY IF EXISTS "Organization creators can add themselves" ON organization_members;
CREATE POLICY "Organization creators can add themselves"
    ON organization_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM organizations
            WHERE organizations.id = organization_members.organization_id
              AND organizations.created_by = auth.uid()
              AND organization_members.user_id = auth.uid()
        )
    );

-- Только админы организации могут управлять участниками (UPDATE, DELETE)
DROP POLICY IF EXISTS "Org admins can manage members" ON organization_members;
CREATE POLICY "Org admins can manage members"
    ON organization_members FOR ALL
    USING (is_org_admin(organization_id, auth.uid()))
    WITH CHECK (is_org_admin(organization_id, auth.uid()));

-- ============================================
-- PROJECTS RLS POLICIES
-- ============================================

-- Пользователь видит только проекты, к которым имеет доступ
-- (На основе docs/01_AUTH_PROJECTS.md: видит если он в project_members ИЛИ он Org Admin)
DROP POLICY IF EXISTS "Users can view accessible projects" ON projects;
CREATE POLICY "Users can view accessible projects"
    ON projects FOR SELECT
    USING (has_project_access(id, auth.uid()));

-- Пользователь может создать проект в организации, если он является участником этой организации
-- Используем функцию is_org_member для предотвращения рекурсии
DROP POLICY IF EXISTS "Users can create projects in their organizations" ON projects;
CREATE POLICY "Users can create projects in their organizations"
    ON projects FOR INSERT
    WITH CHECK (
        is_org_member(organization_id, auth.uid())
        AND created_by = auth.uid()
    );

-- Проект могут обновлять: админы организации ИЛИ project_owner
-- Используем функцию для предотвращения рекурсии
DROP POLICY IF EXISTS "Project owners and org admins can update projects" ON projects;
CREATE POLICY "Project owners and org admins can update projects"
    ON projects FOR UPDATE
    USING (
        is_org_admin(organization_id, auth.uid()) OR
        is_project_owner(id, auth.uid())
    );

-- Проект могут удалять: админы организации ИЛИ project_owner
-- Используем функцию для предотвращения рекурсии
DROP POLICY IF EXISTS "Project owners and org admins can delete projects" ON projects;
CREATE POLICY "Project owners and org admins can delete projects"
    ON projects FOR DELETE
    USING (
        is_org_admin(organization_id, auth.uid()) OR
        is_project_owner(id, auth.uid())
    );

-- ============================================
-- PROJECT MEMBERS RLS POLICIES
-- ============================================

-- Пользователь видит участников проектов, к которым имеет доступ
DROP POLICY IF EXISTS "Users can view members of accessible projects" ON project_members;
CREATE POLICY "Users can view members of accessible projects"
    ON project_members FOR SELECT
    USING (has_project_access(project_id, auth.uid()));

-- Управлять участниками проекта могут: админы организации ИЛИ project_owner
-- Используем функции для предотвращения рекурсии
DROP POLICY IF EXISTS "Project owners and org admins can manage project members" ON project_members;
CREATE POLICY "Project owners and org admins can manage project members"
    ON project_members FOR ALL
    USING (
        is_org_admin((SELECT organization_id FROM projects WHERE id = project_id), auth.uid()) OR
        is_project_owner(project_id, auth.uid())
    )
    WITH CHECK (
        is_org_admin((SELECT organization_id FROM projects WHERE id = project_id), auth.uid()) OR
        is_project_owner(project_id, auth.uid())
    );

-- ============================================
-- ДОКУМЕНТЫ И СЕКЦИИ (RAG и структурный подход)
-- ============================================

-- 1. Включаем расширение для векторов (если еще нет)
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Таблица документов (метаданные) - скорее всего уже есть, но проверим
CREATE TABLE IF NOT EXISTS source_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  storage_path TEXT NOT NULL, -- путь в бакете Supabase
  doc_type TEXT, -- 'Protocol', 'SAP', 'Brochure'
  status TEXT DEFAULT 'uploading', -- 'indexed', 'error'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Добавление колонок для метаданных парсинга и качества
ALTER TABLE source_documents 
ADD COLUMN IF NOT EXISTS parsing_metadata JSONB DEFAULT '{}', -- Техн. метрики (время, кол-во страниц)
ADD COLUMN IF NOT EXISTS parsing_quality_score INT,           -- Оценка пользователя (1-5)
ADD COLUMN IF NOT EXISTS parsing_quality_comment TEXT,        -- Комментарий к ошибке
ADD COLUMN IF NOT EXISTS detected_tables_count INT DEFAULT 0; -- Сколько таблиц нашел Docling

-- Индексы для source_documents
CREATE INDEX IF NOT EXISTS idx_source_documents_project_id ON source_documents(project_id);
CREATE INDEX IF NOT EXISTS idx_source_documents_status ON source_documents(status);
CREATE INDEX IF NOT EXISTS idx_source_documents_doc_type ON source_documents(doc_type);

COMMENT ON COLUMN source_documents.parsing_metadata IS 'Технические метаданные парсинга (JSONB): время обработки, количество страниц, ошибки';
COMMENT ON COLUMN source_documents.parsing_quality_score IS 'Ручная оценка качества парсинга (1-5)';
COMMENT ON COLUMN source_documents.parsing_quality_comment IS 'Комментарий к оценке качества парсинга';

-- 3. Справочник канонических секций (таксономия)
CREATE TABLE IF NOT EXISTS canonical_sections (
  code TEXT PRIMARY KEY, -- например "INCLUSION_CRITERIA", "EXCLUSION_CRITERIA"
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE canonical_sections IS 'Справочник канонических секций документов (таксономия)';
COMMENT ON COLUMN canonical_sections.code IS 'Уникальный код секции (например, INCLUSION_CRITERIA)';

-- 4. Справочник канонических якорей (для классификации секций)
CREATE TABLE IF NOT EXISTS canonical_anchors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_code TEXT NOT NULL REFERENCES canonical_sections(code) ON DELETE CASCADE,
  anchor_text TEXT NOT NULL, -- Текст-якорь для классификации
  embedding vector(1536), -- Векторное представление якоря
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_canonical_anchors_code ON canonical_anchors(canonical_code);
CREATE INDEX IF NOT EXISTS idx_canonical_anchors_embedding ON canonical_anchors USING ivfflat (embedding vector_cosine_ops);

COMMENT ON TABLE canonical_anchors IS 'Справочник якорей для классификации секций документов';
COMMENT ON COLUMN canonical_anchors.anchor_text IS 'Текст-якорь для сопоставления с секциями документов';
COMMENT ON COLUMN canonical_anchors.embedding IS 'Векторное представление якоря для семантического поиска';

-- 5. Таблица СЕКЦИЙ (Самое важное для структурного подхода)
-- Создаем как document_sections, если она не существует и source_sections тоже не существует
DO $$
BEGIN
    -- Создаем таблицу только если обе таблицы не существуют
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_sections')
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
        CREATE TABLE document_sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID REFERENCES source_documents(id) ON DELETE CASCADE,
  
  -- Структурные поля
  section_number TEXT, -- например "3.1.2"
  header TEXT,         -- например "Критерии включения"
  page_number INT,
  
  -- Контент
  content_text TEXT,     -- Чистый текст для поиска
  content_markdown TEXT, -- Текст с разметкой таблиц (для LLM)
  
  -- Вектор для гибридного поиска (опционально)
  embedding vector(1536),
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);
    END IF;
END $$;

-- Добавление полей классификации к существующей таблице
-- Выполняется только если таблица document_sections существует (до переименования)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_sections') THEN
ALTER TABLE document_sections 
ADD COLUMN IF NOT EXISTS canonical_code TEXT REFERENCES canonical_sections(code) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS classification_confidence FLOAT; -- Уверенность классификации (0.0-1.0)
    END IF;
END $$;

-- Создание индексов (выполняется только если таблица document_sections существует)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_sections') THEN
CREATE INDEX IF NOT EXISTS idx_document_sections_document_id ON document_sections(document_id);
CREATE INDEX IF NOT EXISTS idx_document_sections_canonical_code ON document_sections(canonical_code);
CREATE INDEX IF NOT EXISTS idx_document_sections_embedding ON document_sections USING ivfflat (embedding vector_cosine_ops);
    END IF;
END $$;

-- Комментарии для document_sections будут обновлены после переименования в source_sections
-- (см. раздел "МИГРАЦИЯ: Refactoring Inputs/Outputs" ниже)

-- 4. Таблица Глобальных переменных (Паспорт исследования)
CREATE TABLE IF NOT EXISTS study_globals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  variable_name TEXT,  -- "Phase", "Drug_Name"
  variable_value TEXT,
  source_section_id UUID, -- Внешний ключ будет добавлен после переименования document_sections -> source_sections
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Включаем RLS (Безопасность)
ALTER TABLE source_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE canonical_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE canonical_anchors ENABLE ROW LEVEL SECURITY;
-- RLS для document_sections будет включен после переименования в source_sections
-- (см. раздел "МИГРАЦИЯ: Refactoring Inputs/Outputs" ниже)
ALTER TABLE study_globals ENABLE ROW LEVEL SECURITY;

-- ============================================
-- SOURCE DOCUMENTS RLS POLICIES
-- ============================================

-- Пользователи могут видеть документы проектов, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can view documents" ON source_documents;
CREATE POLICY "Project members can view documents"
ON source_documents FOR SELECT
USING (has_project_access(project_id, auth.uid()));

-- Пользователи могут создавать документы в проектах, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can create documents" ON source_documents;
CREATE POLICY "Project members can create documents"
ON source_documents FOR INSERT
WITH CHECK (has_project_access(project_id, auth.uid()));

-- Редактировать документы могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can update documents" ON source_documents;
CREATE POLICY "Project editors can update documents"
ON source_documents FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM project_members
    WHERE project_members.project_id = source_documents.project_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- ============================================
-- CANONICAL SECTIONS RLS POLICIES
-- ============================================

-- Справочник канонических секций доступен всем авторизованным пользователям для чтения
DROP POLICY IF EXISTS "Authenticated users can view canonical sections" ON canonical_sections;
CREATE POLICY "Authenticated users can view canonical sections"
ON canonical_sections FOR SELECT
USING (auth.role() = 'authenticated');

-- Только админы могут управлять справочником (в будущем можно расширить)
DROP POLICY IF EXISTS "Admins can manage canonical sections" ON canonical_sections;
CREATE POLICY "Admins can manage canonical sections"
ON canonical_sections FOR ALL
USING (false) -- Пока отключено, можно добавить проверку на суперадмина
WITH CHECK (false);

-- ============================================
-- CANONICAL ANCHORS RLS POLICIES
-- ============================================

-- Справочник якорей доступен всем авторизованным пользователям для чтения
DROP POLICY IF EXISTS "Authenticated users can view canonical anchors" ON canonical_anchors;
CREATE POLICY "Authenticated users can view canonical anchors"
ON canonical_anchors FOR SELECT
USING (auth.role() = 'authenticated');

-- Только админы могут управлять справочником
DROP POLICY IF EXISTS "Admins can manage canonical anchors" ON canonical_anchors;
CREATE POLICY "Admins can manage canonical anchors"
ON canonical_anchors FOR ALL
USING (false) -- Пока отключено
WITH CHECK (false);

-- ============================================
-- DOCUMENT SECTIONS RLS POLICIES
-- ============================================
-- ПРИМЕЧАНИЕ: Политики для document_sections создаются после переименования таблицы в source_sections
-- (см. раздел "МИГРАЦИЯ: Refactoring Inputs/Outputs" ниже)
-- Здесь политики не создаются, чтобы избежать ошибок при повторном выполнении скрипта

-- ============================================
-- STUDY GLOBALS RLS POLICIES
-- ============================================

-- Пользователи могут видеть глобальные переменные проектов, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can view study globals" ON study_globals;
CREATE POLICY "Project members can view study globals"
ON study_globals FOR SELECT
USING (has_project_access(project_id, auth.uid()));

-- Создавать глобальные переменные могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can create study globals" ON study_globals;
CREATE POLICY "Project editors can create study globals"
ON study_globals FOR INSERT
WITH CHECK (
  has_project_access(project_id, auth.uid())
  AND
  EXISTS (
    SELECT 1 FROM project_members
    WHERE project_members.project_id = study_globals.project_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- Обновлять глобальные переменные могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can update study globals" ON study_globals;
CREATE POLICY "Project editors can update study globals"
ON study_globals FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM project_members
    WHERE project_members.project_id = study_globals.project_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- ============================================
-- ГРАФ ШАБЛОНОВ (Template Graph Architecture)
-- Золотые стандарты структур документов и связи между ними
-- ============================================

-- 1. Таблица типов документов (шаблоны)
CREATE TABLE IF NOT EXISTS doc_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL, -- например, 'Protocol_EAEU', 'CSR_ICH_E3'
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doc_templates_name ON doc_templates(name);

COMMENT ON TABLE doc_templates IS 'Типы документов (шаблоны) - золотые стандарты структур';
COMMENT ON COLUMN doc_templates.name IS 'Уникальное имя шаблона (например, Protocol_EAEU, CSR_ICH_E3)';
COMMENT ON COLUMN doc_templates.description IS 'Описание назначения шаблона';

-- 2. Таблица узлов графа (структура шаблона)
CREATE TABLE IF NOT EXISTS template_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES doc_templates(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES template_sections(id) ON DELETE CASCADE, -- для древовидной структуры
    section_number TEXT, -- например, "3.1"
    title TEXT NOT NULL, -- название секции
    description TEXT, -- инструкция для AI (о чем эта секция)
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    embedding vector(1536), -- для семантического поиска секции при парсинге
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_template_sections_template_id ON template_sections(template_id);
CREATE INDEX IF NOT EXISTS idx_template_sections_parent_id ON template_sections(parent_id);
CREATE INDEX IF NOT EXISTS idx_template_sections_embedding ON template_sections USING ivfflat (embedding vector_cosine_ops);

COMMENT ON TABLE template_sections IS 'Узлы графа шаблонов - структура секций документа';
COMMENT ON COLUMN template_sections.parent_id IS 'Родительская секция для построения древовидной структуры';
COMMENT ON COLUMN template_sections.section_number IS 'Номер секции в шаблоне (например, "3.1")';
COMMENT ON COLUMN template_sections.description IS 'Инструкция для AI о содержании секции';
COMMENT ON COLUMN template_sections.is_mandatory IS 'Обязательная ли секция в шаблоне';
COMMENT ON COLUMN template_sections.embedding IS 'Векторное представление секции для семантического поиска при парсинге';

-- 3. Таблица ребер графа (правила переноса между секциями)
CREATE TABLE IF NOT EXISTS section_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_section_id UUID NOT NULL REFERENCES template_sections(id) ON DELETE CASCADE,
    target_section_id UUID NOT NULL REFERENCES template_sections(id) ON DELETE CASCADE,
    relationship_type TEXT NOT NULL CHECK (relationship_type IN ('direct_copy', 'summary', 'transformation', 'consistency_check')),
    instruction TEXT, -- промпт для трансформации (например, "change future to past tense")
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (source_section_id != target_section_id) -- предотвращаем петли
);

CREATE INDEX IF NOT EXISTS idx_section_mappings_source ON section_mappings(source_section_id);
CREATE INDEX IF NOT EXISTS idx_section_mappings_target ON section_mappings(target_section_id);
CREATE INDEX IF NOT EXISTS idx_section_mappings_type ON section_mappings(relationship_type);

COMMENT ON TABLE section_mappings IS 'Ребра графа шаблонов - правила переноса данных между секциями';
COMMENT ON COLUMN section_mappings.source_section_id IS 'Исходная секция шаблона';
COMMENT ON COLUMN section_mappings.target_section_id IS 'Целевая секция шаблона';
COMMENT ON COLUMN section_mappings.relationship_type IS 'Тип связи: direct_copy, summary, transformation, consistency_check';
COMMENT ON COLUMN section_mappings.instruction IS 'Промпт для AI при трансформации данных между секциями';

-- 4. Модификация существующей таблицы document_sections
-- Добавляем связь с шаблоном секции (выполнится после переименования в source_sections)
-- См. раздел "МИГРАЦИЯ: Refactoring Inputs/Outputs" ниже

-- ============================================
-- RLS для таблиц графа шаблонов
-- ============================================

ALTER TABLE doc_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE template_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE section_mappings ENABLE ROW LEVEL SECURITY;

-- ============================================
-- DOC TEMPLATES RLS POLICIES
-- ============================================

-- Шаблоны доступны всем авторизованным пользователям для чтения
DROP POLICY IF EXISTS "Authenticated users can view doc templates" ON doc_templates;
CREATE POLICY "Authenticated users can view doc templates"
ON doc_templates FOR SELECT
USING (auth.role() = 'authenticated');

-- Только админы могут управлять шаблонами (в будущем можно расширить)
DROP POLICY IF EXISTS "Admins can manage doc templates" ON doc_templates;
CREATE POLICY "Admins can manage doc templates"
ON doc_templates FOR ALL
USING (false) -- Пока отключено, можно добавить проверку на суперадмина
WITH CHECK (false);

-- ============================================
-- TEMPLATE SECTIONS RLS POLICIES
-- ============================================

-- Секции шаблонов доступны всем авторизованным пользователям для чтения
DROP POLICY IF EXISTS "Authenticated users can view template sections" ON template_sections;
CREATE POLICY "Authenticated users can view template sections"
ON template_sections FOR SELECT
USING (auth.role() = 'authenticated');

-- Только админы могут управлять секциями шаблонов
DROP POLICY IF EXISTS "Admins can manage template sections" ON template_sections;
CREATE POLICY "Admins can manage template sections"
ON template_sections FOR ALL
USING (false) -- Пока отключено
WITH CHECK (false);

-- ============================================
-- SECTION MAPPINGS RLS POLICIES
-- ============================================

-- Маппинги секций доступны всем авторизованным пользователям для чтения
DROP POLICY IF EXISTS "Authenticated users can view section mappings" ON section_mappings;
CREATE POLICY "Authenticated users can view section mappings"
ON section_mappings FOR SELECT
USING (auth.role() = 'authenticated');

-- Только админы могут управлять маппингами
DROP POLICY IF EXISTS "Admins can manage section mappings" ON section_mappings;
CREATE POLICY "Admins can manage section mappings"
ON section_mappings FOR ALL
USING (false) -- Пока отключено
WITH CHECK (false);

-- ============================================
-- МИГРАЦИЯ: Refactoring Inputs/Outputs
-- Переименование document_sections -> source_sections
-- Создание таблиц для Deliverables (Outputs)
-- ============================================

-- ============================================
-- 1. Удаление старых политик RLS для document_sections
-- ============================================
-- Удаляем политики только если таблица document_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_sections') THEN
DROP POLICY IF EXISTS "Project members can read sections" ON document_sections;
DROP POLICY IF EXISTS "Project editors can create sections" ON document_sections;
DROP POLICY IF EXISTS "Project editors can update sections" ON document_sections;
    END IF;
END $$;

-- ============================================
-- 2. Обновление внешнего ключа в study_globals
-- ============================================
-- Сначала удаляем старый внешний ключ (если он существует)
ALTER TABLE study_globals 
DROP CONSTRAINT IF EXISTS study_globals_source_section_id_fkey;

-- Добавим новый внешний ключ после переименования таблицы
-- (выполнится ниже после переименования)

-- ============================================
-- 3. Переименование таблицы document_sections -> source_sections
-- ============================================
-- Переименовываем только если таблица document_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_sections') THEN
ALTER TABLE document_sections RENAME TO source_sections;
    END IF;
END $$;

-- Переименование индексов (только если они существуют)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_document_sections_document_id') THEN
        ALTER INDEX idx_document_sections_document_id RENAME TO idx_source_sections_document_id;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_document_sections_canonical_code') THEN
        ALTER INDEX idx_document_sections_canonical_code RENAME TO idx_source_sections_canonical_code;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_document_sections_template_section_id') THEN
        ALTER INDEX idx_document_sections_template_section_id RENAME TO idx_source_sections_template_section_id;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_document_sections_embedding') THEN
        ALTER INDEX idx_document_sections_embedding RENAME TO idx_source_sections_embedding;
    END IF;
END $$;

-- Добавление колонки template_section_id и других колонок (если еще не добавлены)
-- Выполняется только если таблица source_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
        -- Добавляем колонки, если их нет
        ALTER TABLE source_sections 
        ADD COLUMN IF NOT EXISTS canonical_code TEXT,
        ADD COLUMN IF NOT EXISTS classification_confidence FLOAT,
        ADD COLUMN IF NOT EXISTS template_section_id UUID;
        
        -- Добавляем внешние ключи, если их нет
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE constraint_name = 'source_sections_canonical_code_fkey'
        ) THEN
            ALTER TABLE source_sections 
            ADD CONSTRAINT source_sections_canonical_code_fkey 
            FOREIGN KEY (canonical_code) REFERENCES canonical_sections(code) ON DELETE SET NULL;
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE constraint_name = 'source_sections_template_section_id_fkey'
        ) THEN
            ALTER TABLE source_sections 
            ADD CONSTRAINT source_sections_template_section_id_fkey 
            FOREIGN KEY (template_section_id) REFERENCES template_sections(id) ON DELETE SET NULL;
        END IF;
        
        -- Создаем индексы, если их нет
        CREATE INDEX IF NOT EXISTS idx_source_sections_document_id ON source_sections(document_id);
        CREATE INDEX IF NOT EXISTS idx_source_sections_canonical_code ON source_sections(canonical_code);
        CREATE INDEX IF NOT EXISTS idx_source_sections_template_section_id ON source_sections(template_section_id);
        CREATE INDEX IF NOT EXISTS idx_source_sections_embedding ON source_sections USING ivfflat (embedding vector_cosine_ops);
    END IF;
END $$;

-- Обновление комментариев (только если таблица существует)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
COMMENT ON TABLE source_sections IS 'Секции исходных документов (Inputs) с классификацией по каноническим секциям';
COMMENT ON COLUMN source_sections.canonical_code IS 'Ссылка на каноническую секцию из справочника';
COMMENT ON COLUMN source_sections.classification_confidence IS 'Уверенность автоматической классификации (0.0-1.0)';
COMMENT ON COLUMN source_sections.template_section_id IS 'Связь с идеальным прототипом секции из шаблона';
    END IF;
END $$;

-- ============================================
-- 4. Восстановление внешнего ключа в study_globals
-- ============================================
-- Добавляем внешний ключ только если таблица source_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
        -- Удаляем старый внешний ключ, если он существует
        ALTER TABLE study_globals 
        DROP CONSTRAINT IF EXISTS study_globals_source_section_id_fkey;
        
        -- Добавляем новый внешний ключ
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE constraint_name = 'study_globals_source_section_id_fkey'
        ) THEN
ALTER TABLE study_globals
ADD CONSTRAINT study_globals_source_section_id_fkey 
FOREIGN KEY (source_section_id) REFERENCES source_sections(id) ON DELETE SET NULL;
        END IF;
    END IF;
END $$;

-- ============================================
-- 5. Включение RLS для source_sections (после переименования)
-- ============================================
-- Включаем RLS только если таблица source_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
        ALTER TABLE source_sections ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- ============================================
-- 6. Восстановление RLS политик для source_sections
-- ============================================
-- Создаем политики только если таблица source_sections существует
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'source_sections') THEN
        -- Удаляем старые политики, если они существуют
        DROP POLICY IF EXISTS "Project members can read sections" ON source_sections;
        DROP POLICY IF EXISTS "Project editors can create sections" ON source_sections;
        DROP POLICY IF EXISTS "Project editors can update sections" ON source_sections;
        
-- Пользователи могут видеть секции документов проектов, к которым имеют доступ
CREATE POLICY "Project members can read sections"
ON source_sections FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM source_documents
    JOIN project_members ON project_members.project_id = source_documents.project_id
    WHERE source_documents.id = source_sections.document_id
    AND project_members.user_id = auth.uid()
  )
  OR
  EXISTS (
    SELECT 1 FROM source_documents
    JOIN projects ON projects.id = source_documents.project_id
    WHERE source_documents.id = source_sections.document_id
    AND is_org_admin(projects.organization_id, auth.uid())
  )
);

-- Создавать секции могут участники проекта с ролью editor или выше
CREATE POLICY "Project editors can create sections"
ON source_sections FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM source_documents
    JOIN project_members ON project_members.project_id = source_documents.project_id
    WHERE source_documents.id = source_sections.document_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- Обновлять секции могут участники проекта с ролью editor или выше
CREATE POLICY "Project editors can update sections"
ON source_sections FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM source_documents
    JOIN project_members ON project_members.project_id = source_documents.project_id
    WHERE source_documents.id = source_sections.document_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);
    END IF;
END $$;

-- ============================================
-- 7. Создание таблицы deliverables (Outputs)
-- ============================================
CREATE TABLE IF NOT EXISTS deliverables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES doc_templates(id) ON DELETE RESTRICT,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'final')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deliverables_project_id ON deliverables(project_id);
CREATE INDEX IF NOT EXISTS idx_deliverables_template_id ON deliverables(template_id);
CREATE INDEX IF NOT EXISTS idx_deliverables_status ON deliverables(status);

COMMENT ON TABLE deliverables IS 'Готовые документы (Outputs/Deliverables), созданные на основе шаблонов';
COMMENT ON COLUMN deliverables.project_id IS 'Проект, к которому относится документ';
COMMENT ON COLUMN deliverables.template_id IS 'Шаблон документа, по которому создан deliverable (например, CSR)';
COMMENT ON COLUMN deliverables.title IS 'Название документа';
COMMENT ON COLUMN deliverables.status IS 'Статус документа: draft (черновик) или final (финальная версия)';

-- Триггер для автоматического обновления updated_at
DROP TRIGGER IF EXISTS update_deliverables_updated_at ON deliverables;
CREATE TRIGGER update_deliverables_updated_at 
    BEFORE UPDATE ON deliverables
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 8. Создание таблицы deliverable_sections
-- ============================================
CREATE TABLE IF NOT EXISTS deliverable_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deliverable_id UUID NOT NULL REFERENCES deliverables(id) ON DELETE CASCADE,
    template_section_id UUID NOT NULL REFERENCES template_sections(id) ON DELETE RESTRICT,
    content_html TEXT, -- HTML контент для редактора Tiptap
    status TEXT NOT NULL DEFAULT 'empty' CHECK (status IN ('empty', 'generated', 'reviewed')),
    used_source_section_ids UUID[] DEFAULT ARRAY[]::UUID[], -- Массив ссылок на source_sections
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deliverable_sections_deliverable_id ON deliverable_sections(deliverable_id);
CREATE INDEX IF NOT EXISTS idx_deliverable_sections_template_section_id ON deliverable_sections(template_section_id);
CREATE INDEX IF NOT EXISTS idx_deliverable_sections_status ON deliverable_sections(status);
-- GIN индекс для массива UUID для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_deliverable_sections_used_source_section_ids ON deliverable_sections USING GIN(used_source_section_ids);

COMMENT ON TABLE deliverable_sections IS 'Секции готовых документов (Outputs) с контентом для редактора';
COMMENT ON COLUMN deliverable_sections.deliverable_id IS 'Документ, к которому относится секция';
COMMENT ON COLUMN deliverable_sections.template_section_id IS 'Связь с секцией шаблона (золотой стандарт)';
COMMENT ON COLUMN deliverable_sections.content_html IS 'HTML контент секции для редактора Tiptap';
COMMENT ON COLUMN deliverable_sections.status IS 'Статус секции: empty (пустая), generated (сгенерирована AI), reviewed (проверена)';
COMMENT ON COLUMN deliverable_sections.used_source_section_ids IS 'Массив ID секций исходных документов (source_sections), использованных для генерации';

-- Триггер для автоматического обновления updated_at
DROP TRIGGER IF EXISTS update_deliverable_sections_updated_at ON deliverable_sections;
CREATE TRIGGER update_deliverable_sections_updated_at 
    BEFORE UPDATE ON deliverable_sections
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 8. Включение RLS для новых таблиц
-- ============================================
ALTER TABLE deliverables ENABLE ROW LEVEL SECURITY;
ALTER TABLE deliverable_sections ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 9. RLS POLICIES для deliverables
-- ============================================

-- Пользователи могут видеть документы проектов, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can view deliverables" ON deliverables;
CREATE POLICY "Project members can view deliverables"
ON deliverables FOR SELECT
USING (has_project_access(project_id, auth.uid()));

-- Пользователи могут создавать документы в проектах, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can create deliverables" ON deliverables;
CREATE POLICY "Project members can create deliverables"
ON deliverables FOR INSERT
WITH CHECK (has_project_access(project_id, auth.uid()));

-- Редактировать документы могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can update deliverables" ON deliverables;
CREATE POLICY "Project editors can update deliverables"
ON deliverables FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM project_members
    WHERE project_members.project_id = deliverables.project_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- Удалять документы могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can delete deliverables" ON deliverables;
CREATE POLICY "Project editors can delete deliverables"
ON deliverables FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM project_members
    WHERE project_members.project_id = deliverables.project_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- ============================================
-- 10. RLS POLICIES для deliverable_sections
-- ============================================

-- Пользователи могут видеть секции документов проектов, к которым имеют доступ
DROP POLICY IF EXISTS "Project members can read deliverable sections" ON deliverable_sections;
CREATE POLICY "Project members can read deliverable sections"
ON deliverable_sections FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM deliverables
    JOIN project_members ON project_members.project_id = deliverables.project_id
    WHERE deliverables.id = deliverable_sections.deliverable_id
    AND project_members.user_id = auth.uid()
  )
  OR
  EXISTS (
    SELECT 1 FROM deliverables
    JOIN projects ON projects.id = deliverables.project_id
    WHERE deliverables.id = deliverable_sections.deliverable_id
    AND is_org_admin(projects.organization_id, auth.uid())
  )
);

-- Создавать секции могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can create deliverable sections" ON deliverable_sections;
CREATE POLICY "Project editors can create deliverable sections"
ON deliverable_sections FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM deliverables
    JOIN project_members ON project_members.project_id = deliverables.project_id
    WHERE deliverables.id = deliverable_sections.deliverable_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- Обновлять секции могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can update deliverable sections" ON deliverable_sections;
CREATE POLICY "Project editors can update deliverable sections"
ON deliverable_sections FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM deliverables
    JOIN project_members ON project_members.project_id = deliverables.project_id
    WHERE deliverables.id = deliverable_sections.deliverable_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- Удалять секции могут участники проекта с ролью editor или выше
DROP POLICY IF EXISTS "Project editors can delete deliverable sections" ON deliverable_sections;
CREATE POLICY "Project editors can delete deliverable sections"
ON deliverable_sections FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM deliverables
    JOIN project_members ON project_members.project_id = deliverables.project_id
    WHERE deliverables.id = deliverable_sections.deliverable_id
    AND project_members.user_id = auth.uid()
    AND project_members.role IN ('project_owner', 'editor')
  )
);

-- ============================================
-- SUPABASE STORAGE POLICIES
-- ============================================
-- Политики доступа для Supabase Storage bucket 'documents'
-- Убедитесь, что bucket 'documents' существует в Supabase Dashboard > Storage

-- Удаляем старые политики (если есть)
DROP POLICY IF EXISTS "Authenticated users can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete documents" ON storage.objects;
DROP POLICY IF EXISTS "Project members can upload to their projects" ON storage.objects;
DROP POLICY IF EXISTS "Project members can read from their projects" ON storage.objects;
DROP POLICY IF EXISTS "Project members can delete from their projects" ON storage.objects;

-- Создаем политики для загрузки файлов
-- Пользователи могут загружать файлы в папки проектов, к которым у них есть доступ

-- Политика для INSERT (загрузка файлов)
CREATE POLICY "Project members can upload to their projects"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents' AND
  (
    -- Проверяем, что путь начинается с 'projects/' и пользователь имеет доступ к проекту
    (storage.foldername(name))[1] = 'projects' AND
    EXISTS (
      SELECT 1 FROM projects
      JOIN project_members ON project_members.project_id = projects.id
      WHERE project_members.user_id = auth.uid()
      AND (storage.foldername(name))[2] = projects.id::text
    )
  )
);

-- Политика для SELECT (чтение файлов)
CREATE POLICY "Project members can read from their projects"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents' AND
  (
    -- Проверяем, что путь начинается с 'projects/' и пользователь имеет доступ к проекту
    (storage.foldername(name))[1] = 'projects' AND
    EXISTS (
      SELECT 1 FROM projects
      JOIN project_members ON project_members.project_id = projects.id
      WHERE project_members.user_id = auth.uid()
      AND (storage.foldername(name))[2] = projects.id::text
    )
  )
);

-- Политика для DELETE (удаление файлов)
CREATE POLICY "Project members can delete from their projects"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'documents' AND
  (
    -- Проверяем, что путь начинается с 'projects/' и пользователь имеет доступ к проекту
    (storage.foldername(name))[1] = 'projects' AND
    EXISTS (
      SELECT 1 FROM projects
      JOIN project_members ON project_members.project_id = projects.id
      WHERE project_members.user_id = auth.uid()
      AND (storage.foldername(name))[2] = projects.id::text
    )
  )
);

COMMENT ON POLICY "Project members can upload to their projects" ON storage.objects IS 'Разрешает участникам проекта загружать файлы в папки своих проектов';
COMMENT ON POLICY "Project members can read from their projects" ON storage.objects IS 'Разрешает участникам проекта читать файлы из папок своих проектов';
COMMENT ON POLICY "Project members can delete from their projects" ON storage.objects IS 'Разрешает участникам проекта удалять файлы из папок своих проектов';

-- Альтернативный вариант: более простая политика для загрузки
-- Если вышеуказанные политики не работают, используйте этот вариант:
-- Раскомментируйте следующие строки и закомментируйте политики выше

-- DROP POLICY IF EXISTS "Project members can upload to their projects" ON storage.objects;
-- DROP POLICY IF EXISTS "Project members can read from their projects" ON storage.objects;
-- DROP POLICY IF EXISTS "Project members can delete from their projects" ON storage.objects;
-- 
-- CREATE POLICY "Authenticated users can upload documents"
-- ON storage.objects FOR INSERT
-- TO authenticated
-- WITH CHECK (bucket_id = 'documents');
-- 
-- CREATE POLICY "Authenticated users can read documents"
-- ON storage.objects FOR SELECT
-- TO authenticated
-- USING (bucket_id = 'documents');
-- 
-- CREATE POLICY "Authenticated users can delete documents"
-- ON storage.objects FOR DELETE
-- TO authenticated
-- USING (bucket_id = 'documents');


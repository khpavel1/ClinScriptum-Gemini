


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";






CREATE TYPE "public"."deliverable_section_status_enum" AS ENUM (
    'empty',
    'draft_ai',
    'in_progress',
    'review',
    'approved'
);


ALTER TYPE "public"."deliverable_section_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."input_type_enum" AS ENUM (
    'file',
    'manual_entry'
);


ALTER TYPE "public"."input_type_enum" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_assign_org_admin"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF NEW.created_by IS NOT NULL THEN
        INSERT INTO organization_members (organization_id, user_id, role)
        VALUES (NEW.id, NEW.created_by, 'org_admin')
        ON CONFLICT (organization_id, user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_assign_org_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_assign_project_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO project_members (project_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'project_owner')
    ON CONFLICT (project_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_assign_project_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_deliverable_section_history"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Создаем запись истории только если изменился контент или статус
    IF OLD.content_html IS DISTINCT FROM NEW.content_html OR OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO deliverable_section_history (
            section_id,
            content_snapshot,
            changed_by_user_id,
            change_reason
        ) VALUES (
            NEW.id,
            NEW.content_html,
            COALESCE(NEW.locked_by_user_id, auth.uid()),
            'Auto-saved: ' || COALESCE(NEW.status::text, 'unknown')
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_deliverable_section_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") IS 'Создает source_document с проверкой доступа (обходит проблему с auth.uid())';



CREATE OR REPLACE FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") IS 'Создает организацию для пользователя (обходит RLS)';



CREATE OR REPLACE FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    new_project_id UUID;
BEGIN
    -- Создаем проект
    INSERT INTO projects (
        study_code,
        title,
        sponsor,
        therapeutic_area,
        status,
        organization_id,
        created_by
    )
    VALUES (
        p_study_code,
        p_title,
        p_sponsor,
        p_therapeutic_area,
        p_status,
        p_organization_id,
        p_created_by
    )
    RETURNING id INTO new_project_id;
    
    -- Триггер auto_assign_project_owner_trigger автоматически добавит создателя как project_owner
    
    RETURN new_project_id;
END;
$$;


ALTER FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") IS 'Создает проект для пользователя (обходит RLS)';



CREATE OR REPLACE FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") IS 'Проверяет, имеет ли пользователь доступ к проекту (как админ организации или как участник проекта)';



CREATE OR REPLACE FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND organization_members.user_id = check_user_id
          AND role = 'org_admin'
    );
END;
$$;


ALTER FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") IS 'Проверяет, является ли пользователь администратором организации';



CREATE OR REPLACE FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = org_id
          AND organization_members.user_id = check_user_id
    );
END;
$$;


ALTER FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") IS 'Проверяет, является ли пользователь участником организации (обходит RLS для предотвращения рекурсии)';



CREATE OR REPLACE FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM project_members
        WHERE project_id = proj_id
          AND project_members.user_id = check_user_id
          AND role = 'project_owner'
    );
END;
$$;


ALTER FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") IS 'Проверяет, является ли пользователь владельцем проекта (обходит RLS для предотвращения рекурсии)';



CREATE OR REPLACE FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer DEFAULT 60) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    unlocked_count INTEGER;
BEGIN
    UPDATE deliverable_sections
    SET locked_by_user_id = NULL,
        locked_at = NULL
    WHERE locked_at IS NOT NULL
    AND locked_at < NOW() - (timeout_minutes || ' minutes')::INTERVAL
    RETURNING id INTO unlocked_count;
    
    RETURN unlocked_count;
END;
$$;


ALTER FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer) IS 'Разблокирует секции, заблокированные более указанного количества минут (для очистки зависших блокировок)';



CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."custom_mappings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "target_custom_section_id" "uuid" NOT NULL,
    "source_custom_section_id" "uuid",
    "source_ideal_section_id" "uuid",
    "instruction" "text",
    "order_index" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "target_ideal_section_id" "uuid",
    CONSTRAINT "custom_mappings_check" CHECK (((("source_custom_section_id" IS NOT NULL) AND ("source_ideal_section_id" IS NULL)) OR (("source_custom_section_id" IS NULL) AND ("source_ideal_section_id" IS NOT NULL))))
);


ALTER TABLE "public"."custom_mappings" OWNER TO "postgres";


COMMENT ON TABLE "public"."custom_mappings" IS 'Правила переноса данных для пользовательских шаблонов';



COMMENT ON COLUMN "public"."custom_mappings"."target_custom_section_id" IS 'Целевая пользовательская секция';



COMMENT ON COLUMN "public"."custom_mappings"."source_custom_section_id" IS 'Исходная пользовательская секция (или NULL)';



COMMENT ON COLUMN "public"."custom_mappings"."source_ideal_section_id" IS 'Исходная идеальная секция (или NULL, взаимоисключающее с source_custom_section_id)';



COMMENT ON COLUMN "public"."custom_mappings"."instruction" IS 'Промпт для AI при трансформации данных';



COMMENT ON COLUMN "public"."custom_mappings"."order_index" IS 'Порядок применения маппинга';



COMMENT ON COLUMN "public"."custom_mappings"."target_ideal_section_id" IS 'Целевая идеальная секция (или NULL)';



CREATE TABLE IF NOT EXISTS "public"."custom_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "custom_template_id" "uuid" NOT NULL,
    "ideal_section_id" "uuid",
    "title" "text" NOT NULL,
    "order_index" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parent_id" "uuid"
);


ALTER TABLE "public"."custom_sections" OWNER TO "postgres";


COMMENT ON TABLE "public"."custom_sections" IS 'Секции пользовательских шаблонов';



COMMENT ON COLUMN "public"."custom_sections"."custom_template_id" IS 'Пользовательский шаблон';



COMMENT ON COLUMN "public"."custom_sections"."ideal_section_id" IS 'Связь с идеальной секцией (может быть NULL)';



COMMENT ON COLUMN "public"."custom_sections"."title" IS 'Название пользовательской секции';



COMMENT ON COLUMN "public"."custom_sections"."order_index" IS 'Порядок отображения секции';



COMMENT ON COLUMN "public"."custom_sections"."parent_id" IS 'Родительская секция для построения древовидной структуры';



CREATE TABLE IF NOT EXISTS "public"."custom_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "base_ideal_template_id" "uuid" NOT NULL,
    "project_id" "uuid",
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."custom_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."custom_templates" IS 'Пользовательские шаблоны (Configuration) - настройки на основе идеальных шаблонов';



COMMENT ON COLUMN "public"."custom_templates"."base_ideal_template_id" IS 'Базовый идеальный шаблон';



COMMENT ON COLUMN "public"."custom_templates"."project_id" IS 'Проект (NULL для глобальных шаблонов организации)';



COMMENT ON COLUMN "public"."custom_templates"."name" IS 'Название пользовательского шаблона';



CREATE TABLE IF NOT EXISTS "public"."deliverable_section_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "section_id" "uuid" NOT NULL,
    "content_snapshot" "text" NOT NULL,
    "changed_by_user_id" "uuid" NOT NULL,
    "change_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."deliverable_section_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."deliverable_section_history" IS 'История изменений секций готовых документов (audit trail)';



COMMENT ON COLUMN "public"."deliverable_section_history"."section_id" IS 'Секция, для которой записана история';



COMMENT ON COLUMN "public"."deliverable_section_history"."content_snapshot" IS 'Снимок HTML контента на момент изменения';



COMMENT ON COLUMN "public"."deliverable_section_history"."changed_by_user_id" IS 'Пользователь, внесший изменение';



COMMENT ON COLUMN "public"."deliverable_section_history"."change_reason" IS 'Причина изменения (AI generation, Manual edit, Review feedback и т.д.)';



CREATE TABLE IF NOT EXISTS "public"."deliverable_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deliverable_id" "uuid" NOT NULL,
    "content_html" "text",
    "status" "text" DEFAULT 'empty'::"text" NOT NULL,
    "used_source_section_ids" "uuid"[] DEFAULT ARRAY[]::"uuid"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "custom_section_id" "uuid",
    "locked_by_user_id" "uuid",
    "locked_at" timestamp with time zone,
    "parent_id" "uuid",
    CONSTRAINT "deliverable_sections_status_check" CHECK (("status" = ANY (ARRAY['empty'::"text", 'generated'::"text", 'reviewed'::"text"])))
);


ALTER TABLE "public"."deliverable_sections" OWNER TO "postgres";


COMMENT ON TABLE "public"."deliverable_sections" IS 'Секции готовых документов (Outputs) с контентом для редактора';



COMMENT ON COLUMN "public"."deliverable_sections"."deliverable_id" IS 'Документ, к которому относится секция';



COMMENT ON COLUMN "public"."deliverable_sections"."content_html" IS 'HTML контент секции для редактора Tiptap';



COMMENT ON COLUMN "public"."deliverable_sections"."status" IS 'Статус секции в workflow: empty, draft_ai, in_progress, review, approved';



COMMENT ON COLUMN "public"."deliverable_sections"."used_source_section_ids" IS 'Массив ID исходных секций (source_sections), использованных для генерации';



COMMENT ON COLUMN "public"."deliverable_sections"."custom_section_id" IS 'Связь с пользовательской секцией шаблона';



COMMENT ON COLUMN "public"."deliverable_sections"."locked_by_user_id" IS 'ID пользователя, заблокировавшего секцию для редактирования';



COMMENT ON COLUMN "public"."deliverable_sections"."locked_at" IS 'Время блокировки секции';



COMMENT ON COLUMN "public"."deliverable_sections"."parent_id" IS 'Родительская секция для построения древовидной структуры';



CREATE TABLE IF NOT EXISTS "public"."deliverables" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "template_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "deliverables_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'final'::"text"])))
);


ALTER TABLE "public"."deliverables" OWNER TO "postgres";


COMMENT ON TABLE "public"."deliverables" IS 'Готовые документы (Outputs/Deliverables), созданные на основе шаблонов';



COMMENT ON COLUMN "public"."deliverables"."project_id" IS 'Проект, к которому относится документ';



COMMENT ON COLUMN "public"."deliverables"."template_id" IS 'Пользовательский шаблон, на основе которого создан deliverable';



COMMENT ON COLUMN "public"."deliverables"."title" IS 'Название документа';



COMMENT ON COLUMN "public"."deliverables"."status" IS 'Статус документа: draft (черновик) или final (финальная версия)';



CREATE TABLE IF NOT EXISTS "public"."ideal_mappings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "target_ideal_section_id" "uuid" NOT NULL,
    "source_ideal_section_id" "uuid" NOT NULL,
    "instruction" "text",
    "order_index" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ideal_mappings_check" CHECK (("target_ideal_section_id" <> "source_ideal_section_id"))
);


ALTER TABLE "public"."ideal_mappings" OWNER TO "postgres";


COMMENT ON TABLE "public"."ideal_mappings" IS 'Правила переноса данных между идеальными секциями';



COMMENT ON COLUMN "public"."ideal_mappings"."target_ideal_section_id" IS 'Целевая идеальная секция';



COMMENT ON COLUMN "public"."ideal_mappings"."source_ideal_section_id" IS 'Исходная идеальная секция';



COMMENT ON COLUMN "public"."ideal_mappings"."instruction" IS 'Промпт для AI при трансформации данных между секциями';



COMMENT ON COLUMN "public"."ideal_mappings"."order_index" IS 'Порядок применения маппинга';



CREATE TABLE IF NOT EXISTS "public"."ideal_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "template_id" "uuid" NOT NULL,
    "parent_id" "uuid",
    "title" "text" NOT NULL,
    "order_index" integer DEFAULT 0 NOT NULL,
    "embedding" "public"."vector"(1536),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ideal_sections" OWNER TO "postgres";


COMMENT ON TABLE "public"."ideal_sections" IS 'Секции идеальных шаблонов (золотые стандарты структур)';



COMMENT ON COLUMN "public"."ideal_sections"."template_id" IS 'Связь с идеальным шаблоном';



COMMENT ON COLUMN "public"."ideal_sections"."parent_id" IS 'Родительская секция для построения древовидной структуры';



COMMENT ON COLUMN "public"."ideal_sections"."title" IS 'Название секции';



COMMENT ON COLUMN "public"."ideal_sections"."order_index" IS 'Порядок отображения секции в шаблоне';



COMMENT ON COLUMN "public"."ideal_sections"."embedding" IS 'Векторное представление секции для семантического поиска';



CREATE TABLE IF NOT EXISTS "public"."ideal_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "group_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ideal_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."ideal_templates" IS 'Идеальные шаблоны (System Master Data) - золотые стандарты структур документов';



COMMENT ON COLUMN "public"."ideal_templates"."name" IS 'Название идеального шаблона (например, "Protocol_EAEU", "CSR_ICH_E3")';



COMMENT ON COLUMN "public"."ideal_templates"."version" IS 'Версия шаблона';



COMMENT ON COLUMN "public"."ideal_templates"."is_active" IS 'Активен ли шаблон (можно отключить старые версии)';



COMMENT ON COLUMN "public"."ideal_templates"."group_id" IS 'ID группы для связывания версий одного шаблона';



CREATE TABLE IF NOT EXISTS "public"."organization_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "organization_members_role_check" CHECK (("role" = ANY (ARRAY['org_admin'::"text", 'member'::"text"])))
);


ALTER TABLE "public"."organization_members" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_members" IS 'Участники организаций с ролями (org_admin, member)';



COMMENT ON COLUMN "public"."organization_members"."role" IS 'Роль в организации: org_admin (управляет пользователями) или member';



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON TABLE "public"."organizations" IS 'Мультитенантные организации для изоляции данных';



COMMENT ON COLUMN "public"."organizations"."slug" IS 'Уникальный идентификатор организации (URL-friendly)';



COMMENT ON COLUMN "public"."organizations"."created_by" IS 'Пользователь, создавший организацию (автоматически становится админом)';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "full_name" "text",
    "avatar_url" "text",
    "organization_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."profiles" IS 'Профили пользователей, расширение таблицы auth.users';



COMMENT ON COLUMN "public"."profiles"."organization_id" IS 'Основная организация пользователя (может быть NULL, т.к. пользователь может быть в нескольких организациях через organization_members)';



CREATE TABLE IF NOT EXISTS "public"."project_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "project_members_role_check" CHECK (("role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text", 'viewer'::"text"])))
);


ALTER TABLE "public"."project_members" OWNER TO "postgres";


COMMENT ON TABLE "public"."project_members" IS 'Участники проектов с ролями (project_owner, editor, viewer)';



COMMENT ON COLUMN "public"."project_members"."role" IS 'Роль в проекте: project_owner (полный доступ), editor (редактирование), viewer (только чтение)';



CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "study_code" "text" NOT NULL,
    "title" "text" NOT NULL,
    "sponsor" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "therapeutic_area" "text",
    CONSTRAINT "projects_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


COMMENT ON TABLE "public"."projects" IS 'Исследования/проекты, привязанные к организациям';



COMMENT ON COLUMN "public"."projects"."study_code" IS 'Уникальный код исследования в рамках организации';



COMMENT ON COLUMN "public"."projects"."sponsor" IS 'Спонсор исследования';



COMMENT ON COLUMN "public"."projects"."status" IS 'Статус проекта: draft (черновик), active (активный), archived (архив)';



COMMENT ON COLUMN "public"."projects"."therapeutic_area" IS 'Терапевтическая область';



CREATE TABLE IF NOT EXISTS "public"."source_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "name" "text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "doc_type" "text",
    "status" "text" DEFAULT 'uploading'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "parsing_metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "parsing_quality_score" integer,
    "parsing_quality_comment" "text",
    "detected_tables_count" integer DEFAULT 0,
    "template_id" "uuid",
    "file_path" "text",
    "input_type" "public"."input_type_enum" DEFAULT 'file'::"public"."input_type_enum",
    "parent_document_id" "uuid",
    "version_label" "text",
    "is_current_version" boolean DEFAULT true
);


ALTER TABLE "public"."source_documents" OWNER TO "postgres";


COMMENT ON COLUMN "public"."source_documents"."parsing_metadata" IS 'Технические метаданные парсинга (JSONB): время обработки, количество страниц, ошибки';



COMMENT ON COLUMN "public"."source_documents"."parsing_quality_score" IS 'Ручная оценка качества парсинга (1-5)';



COMMENT ON COLUMN "public"."source_documents"."parsing_quality_comment" IS 'Комментарий к оценке качества парсинга';



COMMENT ON COLUMN "public"."source_documents"."template_id" IS 'Пользовательский шаблон для классификации документа';



COMMENT ON COLUMN "public"."source_documents"."file_path" IS 'Путь к файлу (может быть NULL для ручного ввода)';



COMMENT ON COLUMN "public"."source_documents"."input_type" IS 'Тип ввода: file (файл) или manual_entry (ручной ввод)';



COMMENT ON COLUMN "public"."source_documents"."parent_document_id" IS 'Родительский документ для версионирования';



COMMENT ON COLUMN "public"."source_documents"."version_label" IS 'Метка версии (например, "v1.0", "v2.1")';



COMMENT ON COLUMN "public"."source_documents"."is_current_version" IS 'Является ли эта версия текущей (default: true)';



CREATE TABLE IF NOT EXISTS "public"."source_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "document_id" "uuid",
    "section_number" "text",
    "header" "text",
    "page_number" integer,
    "content_text" "text",
    "content_markdown" "text",
    "embedding" "public"."vector"(1536),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "classification_confidence" double precision,
    "custom_section_id" "uuid",
    "bbox" "jsonb",
    "template_section_id" "uuid"
);


ALTER TABLE "public"."source_sections" OWNER TO "postgres";


COMMENT ON TABLE "public"."source_sections" IS 'Секции исходных документов (Inputs) с классификацией по каноническим секциям';



COMMENT ON COLUMN "public"."source_sections"."classification_confidence" IS 'Уверенность автоматической классификации (0.0-1.0)';



COMMENT ON COLUMN "public"."source_sections"."custom_section_id" IS 'Связь с пользовательской секцией шаблона (custom_sections)';



COMMENT ON COLUMN "public"."source_sections"."bbox" IS 'Координаты текста в формате JSONB: {"page": 1, "x": 100, "y": 200, "w": 300, "h": 50} для подсветки в PDF';



COMMENT ON COLUMN "public"."source_sections"."template_section_id" IS 'Связь с пользовательской секцией шаблона (custom_sections)';



CREATE TABLE IF NOT EXISTS "public"."study_globals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "variable_name" "text",
    "variable_value" "text",
    "source_section_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."study_globals" OWNER TO "postgres";


ALTER TABLE ONLY "public"."custom_mappings"
    ADD CONSTRAINT "custom_mappings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_sections"
    ADD CONSTRAINT "custom_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_templates"
    ADD CONSTRAINT "custom_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deliverable_section_history"
    ADD CONSTRAINT "deliverable_section_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deliverable_sections"
    ADD CONSTRAINT "deliverable_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deliverables"
    ADD CONSTRAINT "deliverables_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."source_sections"
    ADD CONSTRAINT "document_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ideal_mappings"
    ADD CONSTRAINT "ideal_mappings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ideal_sections"
    ADD CONSTRAINT "ideal_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ideal_templates"
    ADD CONSTRAINT "ideal_templates_name_version_key" UNIQUE ("name", "version");



ALTER TABLE ONLY "public"."ideal_templates"
    ADD CONSTRAINT "ideal_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_organization_id_user_id_key" UNIQUE ("organization_id", "user_id");



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_user_id_key" UNIQUE ("project_id", "user_id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_organization_id_study_code_key" UNIQUE ("organization_id", "study_code");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."source_documents"
    ADD CONSTRAINT "source_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."study_globals"
    ADD CONSTRAINT "study_globals_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_custom_mappings_order" ON "public"."custom_mappings" USING "btree" ("target_custom_section_id", "order_index");



CREATE INDEX "idx_custom_mappings_source_custom" ON "public"."custom_mappings" USING "btree" ("source_custom_section_id");



CREATE INDEX "idx_custom_mappings_source_ideal" ON "public"."custom_mappings" USING "btree" ("source_ideal_section_id");



CREATE INDEX "idx_custom_mappings_target" ON "public"."custom_mappings" USING "btree" ("target_custom_section_id");



CREATE INDEX "idx_custom_mappings_target_ideal" ON "public"."custom_mappings" USING "btree" ("target_ideal_section_id");



CREATE INDEX "idx_custom_sections_custom_template_id" ON "public"."custom_sections" USING "btree" ("custom_template_id");



CREATE INDEX "idx_custom_sections_ideal_section_id" ON "public"."custom_sections" USING "btree" ("ideal_section_id");



CREATE INDEX "idx_custom_sections_order_index" ON "public"."custom_sections" USING "btree" ("custom_template_id", "order_index");



CREATE INDEX "idx_custom_sections_parent_id" ON "public"."custom_sections" USING "btree" ("parent_id");



CREATE INDEX "idx_custom_templates_base_ideal" ON "public"."custom_templates" USING "btree" ("base_ideal_template_id");



CREATE INDEX "idx_custom_templates_project_id" ON "public"."custom_templates" USING "btree" ("project_id");



CREATE INDEX "idx_deliverable_section_history_changed_by" ON "public"."deliverable_section_history" USING "btree" ("changed_by_user_id");



CREATE INDEX "idx_deliverable_section_history_created_at" ON "public"."deliverable_section_history" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_deliverable_section_history_section_id" ON "public"."deliverable_section_history" USING "btree" ("section_id");



CREATE INDEX "idx_deliverable_sections_custom_section_id" ON "public"."deliverable_sections" USING "btree" ("custom_section_id");



CREATE INDEX "idx_deliverable_sections_deliverable_id" ON "public"."deliverable_sections" USING "btree" ("deliverable_id");



CREATE INDEX "idx_deliverable_sections_locked_by" ON "public"."deliverable_sections" USING "btree" ("locked_by_user_id");



CREATE INDEX "idx_deliverable_sections_parent_id" ON "public"."deliverable_sections" USING "btree" ("parent_id");



CREATE INDEX "idx_deliverable_sections_status" ON "public"."deliverable_sections" USING "btree" ("status");



CREATE INDEX "idx_deliverable_sections_used_source_section_ids" ON "public"."deliverable_sections" USING "gin" ("used_source_section_ids");



CREATE INDEX "idx_deliverables_project_id" ON "public"."deliverables" USING "btree" ("project_id");



CREATE INDEX "idx_deliverables_status" ON "public"."deliverables" USING "btree" ("status");



CREATE INDEX "idx_deliverables_template_id" ON "public"."deliverables" USING "btree" ("template_id");



CREATE INDEX "idx_ideal_mappings_order" ON "public"."ideal_mappings" USING "btree" ("target_ideal_section_id", "order_index");



CREATE INDEX "idx_ideal_mappings_source" ON "public"."ideal_mappings" USING "btree" ("source_ideal_section_id");



CREATE INDEX "idx_ideal_mappings_target" ON "public"."ideal_mappings" USING "btree" ("target_ideal_section_id");



CREATE INDEX "idx_ideal_sections_embedding" ON "public"."ideal_sections" USING "ivfflat" ("embedding" "public"."vector_cosine_ops") WHERE ("embedding" IS NOT NULL);



CREATE INDEX "idx_ideal_sections_order_index" ON "public"."ideal_sections" USING "btree" ("template_id", "order_index");



CREATE INDEX "idx_ideal_sections_parent_id" ON "public"."ideal_sections" USING "btree" ("parent_id");



CREATE INDEX "idx_ideal_sections_template_id" ON "public"."ideal_sections" USING "btree" ("template_id");



CREATE INDEX "idx_ideal_templates_group_id" ON "public"."ideal_templates" USING "btree" ("group_id");



CREATE INDEX "idx_ideal_templates_is_active" ON "public"."ideal_templates" USING "btree" ("is_active");



CREATE INDEX "idx_ideal_templates_name" ON "public"."ideal_templates" USING "btree" ("name");



CREATE INDEX "idx_org_members_org_id" ON "public"."organization_members" USING "btree" ("organization_id");



CREATE INDEX "idx_org_members_role" ON "public"."organization_members" USING "btree" ("organization_id", "role");



CREATE INDEX "idx_org_members_user_id" ON "public"."organization_members" USING "btree" ("user_id");



CREATE INDEX "idx_organizations_created_by" ON "public"."organizations" USING "btree" ("created_by");



CREATE INDEX "idx_organizations_slug" ON "public"."organizations" USING "btree" ("slug");



CREATE INDEX "idx_profiles_email" ON "public"."profiles" USING "btree" ("email");



CREATE INDEX "idx_profiles_organization_id" ON "public"."profiles" USING "btree" ("organization_id");



CREATE INDEX "idx_project_members_project_id" ON "public"."project_members" USING "btree" ("project_id");



CREATE INDEX "idx_project_members_role" ON "public"."project_members" USING "btree" ("project_id", "role");



CREATE INDEX "idx_project_members_user_id" ON "public"."project_members" USING "btree" ("user_id");



CREATE INDEX "idx_projects_created_by" ON "public"."projects" USING "btree" ("created_by");



CREATE INDEX "idx_projects_organization_id" ON "public"."projects" USING "btree" ("organization_id");



CREATE INDEX "idx_projects_status" ON "public"."projects" USING "btree" ("status");



CREATE INDEX "idx_projects_study_code" ON "public"."projects" USING "btree" ("study_code");



CREATE INDEX "idx_source_documents_doc_type" ON "public"."source_documents" USING "btree" ("doc_type");



CREATE INDEX "idx_source_documents_input_type" ON "public"."source_documents" USING "btree" ("input_type");



CREATE INDEX "idx_source_documents_is_current_version" ON "public"."source_documents" USING "btree" ("is_current_version");



CREATE INDEX "idx_source_documents_parent_document_id" ON "public"."source_documents" USING "btree" ("parent_document_id");



CREATE INDEX "idx_source_documents_project_id" ON "public"."source_documents" USING "btree" ("project_id");



CREATE INDEX "idx_source_documents_status" ON "public"."source_documents" USING "btree" ("status");



CREATE INDEX "idx_source_documents_template_id" ON "public"."source_documents" USING "btree" ("template_id");



CREATE INDEX "idx_source_sections_bbox" ON "public"."source_sections" USING "gin" ("bbox") WHERE ("bbox" IS NOT NULL);



CREATE INDEX "idx_source_sections_custom_section_id" ON "public"."source_sections" USING "btree" ("custom_section_id");



CREATE INDEX "idx_source_sections_document_id" ON "public"."source_sections" USING "btree" ("document_id");



CREATE INDEX "idx_source_sections_embedding" ON "public"."source_sections" USING "ivfflat" ("embedding" "public"."vector_cosine_ops");



CREATE OR REPLACE TRIGGER "auto_assign_org_admin_trigger" AFTER INSERT ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."auto_assign_org_admin"();



CREATE OR REPLACE TRIGGER "auto_assign_project_owner_trigger" AFTER INSERT ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."auto_assign_project_owner"();



CREATE OR REPLACE TRIGGER "deliverable_section_history_trigger" AFTER UPDATE ON "public"."deliverable_sections" FOR EACH ROW WHEN ((("old"."content_html" IS DISTINCT FROM "new"."content_html") OR ("old"."status" IS DISTINCT FROM "new"."status"))) EXECUTE FUNCTION "public"."create_deliverable_section_history"();



CREATE OR REPLACE TRIGGER "update_custom_sections_updated_at" BEFORE UPDATE ON "public"."custom_sections" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_custom_templates_updated_at" BEFORE UPDATE ON "public"."custom_templates" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_deliverable_sections_updated_at" BEFORE UPDATE ON "public"."deliverable_sections" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_deliverables_updated_at" BEFORE UPDATE ON "public"."deliverables" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_ideal_sections_updated_at" BEFORE UPDATE ON "public"."ideal_sections" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_ideal_templates_updated_at" BEFORE UPDATE ON "public"."ideal_templates" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_organizations_updated_at" BEFORE UPDATE ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_projects_updated_at" BEFORE UPDATE ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."custom_mappings"
    ADD CONSTRAINT "custom_mappings_source_custom_section_id_fkey" FOREIGN KEY ("source_custom_section_id") REFERENCES "public"."custom_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_mappings"
    ADD CONSTRAINT "custom_mappings_source_ideal_section_id_fkey" FOREIGN KEY ("source_ideal_section_id") REFERENCES "public"."ideal_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_mappings"
    ADD CONSTRAINT "custom_mappings_target_custom_section_id_fkey" FOREIGN KEY ("target_custom_section_id") REFERENCES "public"."custom_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_mappings"
    ADD CONSTRAINT "custom_mappings_target_ideal_section_id_fkey" FOREIGN KEY ("target_ideal_section_id") REFERENCES "public"."ideal_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_sections"
    ADD CONSTRAINT "custom_sections_custom_template_id_fkey" FOREIGN KEY ("custom_template_id") REFERENCES "public"."custom_templates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_sections"
    ADD CONSTRAINT "custom_sections_ideal_section_id_fkey" FOREIGN KEY ("ideal_section_id") REFERENCES "public"."ideal_sections"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."custom_sections"
    ADD CONSTRAINT "custom_sections_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."custom_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_templates"
    ADD CONSTRAINT "custom_templates_base_ideal_template_id_fkey" FOREIGN KEY ("base_ideal_template_id") REFERENCES "public"."ideal_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."custom_templates"
    ADD CONSTRAINT "custom_templates_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliverable_section_history"
    ADD CONSTRAINT "deliverable_section_history_changed_by_user_id_fkey" FOREIGN KEY ("changed_by_user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."deliverable_section_history"
    ADD CONSTRAINT "deliverable_section_history_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "public"."deliverable_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliverable_sections"
    ADD CONSTRAINT "deliverable_sections_custom_section_id_fkey" FOREIGN KEY ("custom_section_id") REFERENCES "public"."custom_sections"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."deliverable_sections"
    ADD CONSTRAINT "deliverable_sections_deliverable_id_fkey" FOREIGN KEY ("deliverable_id") REFERENCES "public"."deliverables"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliverable_sections"
    ADD CONSTRAINT "deliverable_sections_locked_by_user_id_fkey" FOREIGN KEY ("locked_by_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."deliverable_sections"
    ADD CONSTRAINT "deliverable_sections_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."deliverable_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliverables"
    ADD CONSTRAINT "deliverables_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliverables"
    ADD CONSTRAINT "deliverables_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."custom_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."source_sections"
    ADD CONSTRAINT "document_sections_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "public"."source_documents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ideal_mappings"
    ADD CONSTRAINT "ideal_mappings_source_ideal_section_id_fkey" FOREIGN KEY ("source_ideal_section_id") REFERENCES "public"."ideal_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ideal_mappings"
    ADD CONSTRAINT "ideal_mappings_target_ideal_section_id_fkey" FOREIGN KEY ("target_ideal_section_id") REFERENCES "public"."ideal_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ideal_sections"
    ADD CONSTRAINT "ideal_sections_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."ideal_sections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ideal_sections"
    ADD CONSTRAINT "ideal_sections_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."ideal_templates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."source_documents"
    ADD CONSTRAINT "source_documents_parent_document_id_fkey" FOREIGN KEY ("parent_document_id") REFERENCES "public"."source_documents"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."source_documents"
    ADD CONSTRAINT "source_documents_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."source_documents"
    ADD CONSTRAINT "source_documents_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."custom_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."source_sections"
    ADD CONSTRAINT "source_sections_custom_section_id_fkey" FOREIGN KEY ("custom_section_id") REFERENCES "public"."custom_sections"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."study_globals"
    ADD CONSTRAINT "study_globals_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."study_globals"
    ADD CONSTRAINT "study_globals_source_section_id_fkey" FOREIGN KEY ("source_section_id") REFERENCES "public"."source_sections"("id") ON DELETE SET NULL;



CREATE POLICY "Admins can manage ideal mappings" ON "public"."ideal_mappings" USING (false) WITH CHECK (false);



CREATE POLICY "Admins can manage ideal sections" ON "public"."ideal_sections" USING (false) WITH CHECK (false);



CREATE POLICY "Admins can manage ideal templates" ON "public"."ideal_templates" USING (false) WITH CHECK (false);



CREATE POLICY "Authenticated users can view ideal mappings" ON "public"."ideal_mappings" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can view ideal sections" ON "public"."ideal_sections" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can view ideal templates" ON "public"."ideal_templates" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Org admins can delete their organizations" ON "public"."organizations" FOR DELETE USING ("public"."is_org_admin"("id", "auth"."uid"()));



CREATE POLICY "Org admins can manage members" ON "public"."organization_members" USING ("public"."is_org_admin"("organization_id", "auth"."uid"())) WITH CHECK ("public"."is_org_admin"("organization_id", "auth"."uid"()));



CREATE POLICY "Org admins can update their organizations" ON "public"."organizations" FOR UPDATE USING ("public"."is_org_admin"("id", "auth"."uid"()));



CREATE POLICY "Organization creators can add themselves" ON "public"."organization_members" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."organizations"
  WHERE (("organizations"."id" = "organization_members"."organization_id") AND ("organizations"."created_by" = "auth"."uid"()) AND ("organization_members"."user_id" = "auth"."uid"())))));



CREATE POLICY "Project editors can create custom sections" ON "public"."custom_sections" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."custom_templates"
  WHERE (("custom_templates"."id" = "custom_sections"."custom_template_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("custom_templates"."project_id" IS NOT NULL) AND "public"."has_project_access"("custom_templates"."project_id", "auth"."uid"())))))));



CREATE POLICY "Project editors can create deliverable sections" ON "public"."deliverable_sections" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."deliverables"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "deliverables"."project_id")))
  WHERE (("deliverables"."id" = "deliverable_sections"."deliverable_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can create sections" ON "public"."source_sections" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."source_documents"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "source_documents"."project_id")))
  WHERE (("source_documents"."id" = "source_sections"."document_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can create study globals" ON "public"."study_globals" FOR INSERT WITH CHECK (("public"."has_project_access"("project_id", "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "study_globals"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"])))))));



CREATE POLICY "Project editors can delete deliverable sections" ON "public"."deliverable_sections" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM ("public"."deliverables"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "deliverables"."project_id")))
  WHERE (("deliverables"."id" = "deliverable_sections"."deliverable_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can delete deliverables" ON "public"."deliverables" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "deliverables"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can manage custom mappings" ON "public"."custom_mappings" USING ((EXISTS ( SELECT 1
   FROM ("public"."custom_sections"
     JOIN "public"."custom_templates" ON (("custom_templates"."id" = "custom_sections"."custom_template_id")))
  WHERE (("custom_sections"."id" = "custom_mappings"."target_custom_section_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("custom_templates"."project_id" IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM "public"."project_members"
          WHERE (("project_members"."project_id" = "custom_templates"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."custom_sections"
     JOIN "public"."custom_templates" ON (("custom_templates"."id" = "custom_sections"."custom_template_id")))
  WHERE (("custom_sections"."id" = "custom_mappings"."target_custom_section_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("custom_templates"."project_id" IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM "public"."project_members"
          WHERE (("project_members"."project_id" = "custom_templates"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"])))))))))));



CREATE POLICY "Project editors can update custom sections" ON "public"."custom_sections" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."custom_templates"
  WHERE (("custom_templates"."id" = "custom_sections"."custom_template_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("custom_templates"."project_id" IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM "public"."project_members"
          WHERE (("project_members"."project_id" = "custom_templates"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"])))))))))));



CREATE POLICY "Project editors can update custom templates" ON "public"."custom_templates" FOR UPDATE USING (((("project_id" IS NULL) AND (EXISTS ( SELECT 1
   FROM "public"."organization_members"
  WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("project_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "custom_templates"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))))));



CREATE POLICY "Project editors can update deliverable sections" ON "public"."deliverable_sections" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM ("public"."deliverables"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "deliverables"."project_id")))
  WHERE (("deliverables"."id" = "deliverable_sections"."deliverable_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can update deliverables" ON "public"."deliverables" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "deliverables"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can update documents" ON "public"."source_documents" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "source_documents"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can update sections" ON "public"."source_sections" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM ("public"."source_documents"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "source_documents"."project_id")))
  WHERE (("source_documents"."id" = "source_sections"."document_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project editors can update study globals" ON "public"."study_globals" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "study_globals"."project_id") AND ("project_members"."user_id" = "auth"."uid"()) AND ("project_members"."role" = ANY (ARRAY['project_owner'::"text", 'editor'::"text"]))))));



CREATE POLICY "Project members can create custom templates" ON "public"."custom_templates" FOR INSERT WITH CHECK (((("project_id" IS NULL) AND (EXISTS ( SELECT 1
   FROM "public"."organization_members"
  WHERE (("organization_members"."user_id" = "auth"."uid"()) AND ("organization_members"."role" = 'org_admin'::"text"))))) OR (("project_id" IS NOT NULL) AND "public"."has_project_access"("project_id", "auth"."uid"()))));



CREATE POLICY "Project members can create deliverables" ON "public"."deliverables" FOR INSERT WITH CHECK ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Project members can create documents" ON "public"."source_documents" FOR INSERT WITH CHECK ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Project members can read deliverable sections" ON "public"."deliverable_sections" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM ("public"."deliverables"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "deliverables"."project_id")))
  WHERE (("deliverables"."id" = "deliverable_sections"."deliverable_id") AND ("project_members"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."deliverables"
     JOIN "public"."projects" ON (("projects"."id" = "deliverables"."project_id")))
  WHERE (("deliverables"."id" = "deliverable_sections"."deliverable_id") AND "public"."is_org_admin"("projects"."organization_id", "auth"."uid"()))))));



CREATE POLICY "Project members can read sections" ON "public"."source_sections" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM ("public"."source_documents"
     JOIN "public"."project_members" ON (("project_members"."project_id" = "source_documents"."project_id")))
  WHERE (("source_documents"."id" = "source_sections"."document_id") AND ("project_members"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."source_documents"
     JOIN "public"."projects" ON (("projects"."id" = "source_documents"."project_id")))
  WHERE (("source_documents"."id" = "source_sections"."document_id") AND "public"."is_org_admin"("projects"."organization_id", "auth"."uid"()))))));



CREATE POLICY "Project members can view deliverables" ON "public"."deliverables" FOR SELECT USING ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Project members can view documents" ON "public"."source_documents" FOR SELECT USING ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Project members can view study globals" ON "public"."study_globals" FOR SELECT USING ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Project owners and org admins can delete projects" ON "public"."projects" FOR DELETE USING (("public"."is_org_admin"("organization_id", "auth"."uid"()) OR "public"."is_project_owner"("id", "auth"."uid"())));



CREATE POLICY "Project owners and org admins can manage project members" ON "public"."project_members" USING (("public"."is_org_admin"(( SELECT "projects"."organization_id"
   FROM "public"."projects"
  WHERE ("projects"."id" = "project_members"."project_id")), "auth"."uid"()) OR "public"."is_project_owner"("project_id", "auth"."uid"()))) WITH CHECK (("public"."is_org_admin"(( SELECT "projects"."organization_id"
   FROM "public"."projects"
  WHERE ("projects"."id" = "project_members"."project_id")), "auth"."uid"()) OR "public"."is_project_owner"("project_id", "auth"."uid"())));



CREATE POLICY "Project owners and org admins can update projects" ON "public"."projects" FOR UPDATE USING (("public"."is_org_admin"("organization_id", "auth"."uid"()) OR "public"."is_project_owner"("id", "auth"."uid"())));



CREATE POLICY "Users can create organizations" ON "public"."organizations" FOR INSERT WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "Users can create projects in their organizations" ON "public"."projects" FOR INSERT WITH CHECK (("public"."is_org_member"("organization_id", "auth"."uid"()) AND ("created_by" = "auth"."uid"())));



CREATE POLICY "Users can create their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can view accessible projects" ON "public"."projects" FOR SELECT USING ("public"."has_project_access"("id", "auth"."uid"()));



CREATE POLICY "Users can view custom mappings" ON "public"."custom_mappings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."custom_sections"
     JOIN "public"."custom_templates" ON (("custom_templates"."id" = "custom_sections"."custom_template_id")))
  WHERE (("custom_sections"."id" = "custom_mappings"."target_custom_section_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE ("organization_members"."user_id" = "auth"."uid"())))) OR (("custom_templates"."project_id" IS NOT NULL) AND "public"."has_project_access"("custom_templates"."project_id", "auth"."uid"())))))));



CREATE POLICY "Users can view custom sections" ON "public"."custom_sections" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."custom_templates"
  WHERE (("custom_templates"."id" = "custom_sections"."custom_template_id") AND ((("custom_templates"."project_id" IS NULL) AND (EXISTS ( SELECT 1
           FROM "public"."organization_members"
          WHERE ("organization_members"."user_id" = "auth"."uid"())))) OR (("custom_templates"."project_id" IS NOT NULL) AND "public"."has_project_access"("custom_templates"."project_id", "auth"."uid"())))))));



CREATE POLICY "Users can view custom templates" ON "public"."custom_templates" FOR SELECT USING (((("project_id" IS NULL) AND (EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE ("projects"."organization_id" IN ( SELECT "organization_members"."organization_id"
           FROM "public"."organization_members"
          WHERE ("organization_members"."user_id" = "auth"."uid"())))))) OR (("project_id" IS NOT NULL) AND "public"."has_project_access"("project_id", "auth"."uid"()))));



CREATE POLICY "Users can view deliverable section history" ON "public"."deliverable_section_history" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."deliverable_sections"
     JOIN "public"."deliverables" ON (("deliverables"."id" = "deliverable_sections"."deliverable_id")))
  WHERE (("deliverable_sections"."id" = "deliverable_section_history"."section_id") AND "public"."has_project_access"("deliverables"."project_id", "auth"."uid"())))));



CREATE POLICY "Users can view members of accessible projects" ON "public"."project_members" FOR SELECT USING ("public"."has_project_access"("project_id", "auth"."uid"()));



CREATE POLICY "Users can view members of their organizations" ON "public"."organization_members" FOR SELECT USING ("public"."is_org_member"("organization_id", "auth"."uid"()));



CREATE POLICY "Users can view profiles in their organizations" ON "public"."profiles" FOR SELECT USING ((("organization_id" IS NOT NULL) AND "public"."is_org_member"("organization_id", "auth"."uid"())));



CREATE POLICY "Users can view their organizations" ON "public"."organizations" FOR SELECT USING ("public"."is_org_member"("id", "auth"."uid"()));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT USING (("id" = "auth"."uid"()));



ALTER TABLE "public"."custom_mappings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."custom_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."custom_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deliverable_section_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deliverable_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deliverables" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ideal_mappings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ideal_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ideal_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."source_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."source_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."study_globals" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."auto_assign_org_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_assign_org_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_assign_org_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_assign_project_owner"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_assign_project_owner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_assign_project_owner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_deliverable_section_history"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_deliverable_section_history"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_deliverable_section_history"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_source_document"("p_project_id" "uuid", "p_name" "text", "p_storage_path" "text", "p_doc_type" "text", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_organization"("org_name" "text", "org_slug" "text", "creator_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_project"("p_study_code" "text", "p_title" "text", "p_sponsor" "text", "p_therapeutic_area" "text", "p_status" "text", "p_organization_id" "uuid", "p_created_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_project_access"("proj_id" "uuid", "check_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_org_admin"("org_id" "uuid", "check_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_org_member"("org_id" "uuid", "check_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_project_owner"("proj_id" "uuid", "check_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."unlock_stale_deliverable_sections"("timeout_minutes" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";












GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";









GRANT ALL ON TABLE "public"."custom_mappings" TO "anon";
GRANT ALL ON TABLE "public"."custom_mappings" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_mappings" TO "service_role";



GRANT ALL ON TABLE "public"."custom_sections" TO "anon";
GRANT ALL ON TABLE "public"."custom_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_sections" TO "service_role";



GRANT ALL ON TABLE "public"."custom_templates" TO "anon";
GRANT ALL ON TABLE "public"."custom_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_templates" TO "service_role";



GRANT ALL ON TABLE "public"."deliverable_section_history" TO "anon";
GRANT ALL ON TABLE "public"."deliverable_section_history" TO "authenticated";
GRANT ALL ON TABLE "public"."deliverable_section_history" TO "service_role";



GRANT ALL ON TABLE "public"."deliverable_sections" TO "anon";
GRANT ALL ON TABLE "public"."deliverable_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."deliverable_sections" TO "service_role";



GRANT ALL ON TABLE "public"."deliverables" TO "anon";
GRANT ALL ON TABLE "public"."deliverables" TO "authenticated";
GRANT ALL ON TABLE "public"."deliverables" TO "service_role";



GRANT ALL ON TABLE "public"."ideal_mappings" TO "anon";
GRANT ALL ON TABLE "public"."ideal_mappings" TO "authenticated";
GRANT ALL ON TABLE "public"."ideal_mappings" TO "service_role";



GRANT ALL ON TABLE "public"."ideal_sections" TO "anon";
GRANT ALL ON TABLE "public"."ideal_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."ideal_sections" TO "service_role";



GRANT ALL ON TABLE "public"."ideal_templates" TO "anon";
GRANT ALL ON TABLE "public"."ideal_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."ideal_templates" TO "service_role";



GRANT ALL ON TABLE "public"."organization_members" TO "anon";
GRANT ALL ON TABLE "public"."organization_members" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_members" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."project_members" TO "anon";
GRANT ALL ON TABLE "public"."project_members" TO "authenticated";
GRANT ALL ON TABLE "public"."project_members" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."source_documents" TO "anon";
GRANT ALL ON TABLE "public"."source_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."source_documents" TO "service_role";



GRANT ALL ON TABLE "public"."source_sections" TO "anon";
GRANT ALL ON TABLE "public"."source_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."source_sections" TO "service_role";



GRANT ALL ON TABLE "public"."study_globals" TO "anon";
GRANT ALL ON TABLE "public"."study_globals" TO "authenticated";
GRANT ALL ON TABLE "public"."study_globals" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































-- ============================================
-- Миграция 003: Права доступа для Admin Interface
-- Управление Ideal Templates
-- ============================================

-- 1. Создание функции проверки супер-админа
-- Для MVP: возвращает TRUE для разработки
-- В будущем можно расширить для проверки:
--   - Списка UUID из таблицы app_admins
--   - Email домена
--   - JWT claims/roles

CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
    -- Для MVP: возвращаем TRUE для всех (разработка)
    -- TODO: Реализовать проверку через таблицу app_admins или JWT claims
    -- Пример будущей реализации:
    -- RETURN EXISTS (
    --     SELECT 1 FROM app_admins 
    --     WHERE user_id = auth.uid()
    -- ) OR (
    --     SELECT email FROM auth.users WHERE id = auth.uid()
    -- ) LIKE '%@admin-domain.com';
    
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION is_super_admin() IS 'Проверяет, является ли текущий пользователь супер-администратором. Для MVP возвращает TRUE для разработки.';

-- ============================================
-- 2. Обновление RLS политик для ideal_templates
-- ============================================

-- Удаление старых политик
DROP POLICY IF EXISTS "Authenticated users can view ideal templates" ON ideal_templates;
DROP POLICY IF EXISTS "Admins can manage ideal templates" ON ideal_templates;

-- Политика: Все могут читать
CREATE POLICY "Allow Read All"
ON ideal_templates FOR SELECT
USING (true);

-- Политика: Только админы могут писать
CREATE POLICY "Allow Write Admin"
ON ideal_templates FOR ALL
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- ============================================
-- 3. Обновление RLS политик для ideal_sections
-- ============================================

-- Удаление старых политик
DROP POLICY IF EXISTS "Authenticated users can view ideal sections" ON ideal_sections;
DROP POLICY IF EXISTS "Admins can manage ideal sections" ON ideal_sections;

-- Политика: Все могут читать
CREATE POLICY "Allow Read All"
ON ideal_sections FOR SELECT
USING (true);

-- Политика: Только админы могут писать
CREATE POLICY "Allow Write Admin"
ON ideal_sections FOR ALL
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- ============================================
-- 4. Обновление RLS политик для ideal_mappings
-- ============================================

-- Удаление старых политик
DROP POLICY IF EXISTS "Authenticated users can view ideal mappings" ON ideal_mappings;
DROP POLICY IF EXISTS "Admins can manage ideal mappings" ON ideal_mappings;

-- Политика: Все могут читать
CREATE POLICY "Allow Read All"
ON ideal_mappings FOR SELECT
USING (true);

-- Политика: Только админы могут писать
CREATE POLICY "Allow Write Admin"
ON ideal_mappings FOR ALL
USING (is_super_admin())
WITH CHECK (is_super_admin());

-- ============================================
-- Примечания:
-- ============================================
-- 1. RLS уже включен для этих таблиц в предыдущих миграциях
-- 2. Функция is_super_admin() использует SECURITY DEFINER для выполнения
--    с правами создателя функции (необходимо для доступа к auth.users)
-- 3. Для продакшена необходимо реализовать проверку через таблицу app_admins
--    или JWT claims вместо возврата TRUE

'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import * as z from 'zod'

// Схема валидации (та же, что в компоненте формы)
const createProjectSchema = z.object({
  studyCode: z.string().min(1, 'Study code is required').max(20, 'Study code must be 20 characters or less'),
  title: z.string().min(1, 'Title is required'),
  sponsor: z.string().min(1, 'Sponsor is required'),
  therapeuticArea: z.string().min(1, 'Therapeutic area is required'),
})

export async function createProject(formData: FormData) {
  const supabase = await createClient()

  // Проверка авторизации
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { error: 'Необходима авторизация' }
  }

  // Получаем или создаем профиль пользователя
  let { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, organization_id, email')
    .eq('id', user.id)
    .single()

  // Если профиля нет, создаем его
  if (profileError || !profile) {
    const { data: newProfile, error: createProfileError } = await supabase
      .from('profiles')
      .insert({
        id: user.id,
        email: user.email || '',
        full_name: user.user_metadata?.full_name || null,
        avatar_url: user.user_metadata?.avatar_url || null,
      })
      .select('id, organization_id, email')
      .single()

    if (createProfileError || !newProfile) {
      return { 
        error: `Ошибка при создании профиля: ${createProfileError?.message || 'Неизвестная ошибка'}` 
      }
    }

    profile = newProfile
  }

  // Если у пользователя нет организации, создаем её автоматически
  if (!profile.organization_id) {
    // Генерируем slug для организации на основе email пользователя
    const emailDomain = user.email?.split('@')[1] || 'user'
    const baseSlug = emailDomain.split('.')[0] || 'org'
    const timestamp = Date.now()
    const orgSlug = `${baseSlug}-${timestamp}`.toLowerCase().replace(/[^a-z0-9-]/g, '-')

    // Создаем организацию через функцию, которая обходит RLS
    const orgName = user.user_metadata?.full_name 
      ? `Организация ${user.user_metadata.full_name}` 
      : `Организация ${user.email}`
    
    const { data: newOrgId, error: orgError } = await supabase
      .rpc('create_user_organization', {
        org_name: orgName,
        org_slug: orgSlug,
        creator_user_id: user.id,
      })

    if (orgError) {
      return { 
        error: `Ошибка при создании организации: ${orgError.message}` 
      }
    }

    if (!newOrgId) {
      return { 
        error: 'Ошибка при создании организации: не получен ID организации' 
      }
    }

    // Получаем созданную организацию
    // Используем прямой запрос, так как функция уже создала организацию
    const { data: newOrg, error: fetchError } = await supabase
      .from('organizations')
      .select()
      .eq('id', newOrgId)
      .single()

    if (fetchError || !newOrg) {
      return { 
        error: `Ошибка при получении организации: ${fetchError?.message || 'Неизвестная ошибка'}` 
      }
    }

    // Обновляем профиль, привязывая его к организации
    const { data: updatedProfile, error: updateError } = await supabase
      .from('profiles')
      .update({ organization_id: newOrg.id })
      .eq('id', user.id)
      .select('id, organization_id, email')
      .single()

    if (updateError || !updatedProfile) {
      return { 
        error: `Ошибка при обновлении профиля: ${updateError?.message || 'Неизвестная ошибка'}` 
      }
    }

    profile = updatedProfile

    // Примечание: триггер auto_assign_org_admin_trigger автоматически добавит пользователя
    // в organization_members с ролью 'org_admin', но проверим на всякий случай
    const { data: existingMember } = await supabase
      .from('organization_members')
      .select('id')
      .eq('organization_id', newOrg.id)
      .eq('user_id', user.id)
      .single()

    if (!existingMember) {
      // Если триггер не сработал, добавляем вручную
      const { error: memberError } = await supabase
        .from('organization_members')
        .insert({
          organization_id: newOrg.id,
          user_id: user.id,
          role: 'org_admin',
        })

      if (memberError) {
        return { 
          error: `Ошибка при добавлении в организацию: ${memberError.message}` 
        }
      }
    }
  }

  // Валидация данных формы
  const rawData = {
    studyCode: formData.get('studyCode') as string,
    title: formData.get('title') as string,
    sponsor: formData.get('sponsor') as string,
    therapeuticArea: formData.get('therapeuticArea') as string,
  }

  const validationResult = createProjectSchema.safeParse(rawData)

  if (!validationResult.success) {
    return {
      error: validationResult.error.errors.map((e) => e.message).join(', '),
    }
  }

  const data = validationResult.data

  // Создание проекта через функцию, которая обходит RLS
  const { data: projectId, error: projectError } = await supabase
    .rpc('create_user_project', {
      p_study_code: data.studyCode,
      p_title: data.title,
      p_sponsor: data.sponsor,
      p_status: 'draft',
      p_organization_id: profile.organization_id,
      p_created_by: profile.id,
    })

  if (projectError) {
    return { error: `Ошибка при создании проекта: ${projectError.message}` }
  }

  if (!projectId) {
    return { error: 'Ошибка при создании проекта: не получен ID проекта' }
  }

  // Обновляем проект, добавляя therapeutic_area
  const { error: updateError } = await supabase
    .from('projects')
    .update({
      therapeutic_area: data.therapeuticArea,
    })
    .eq('id', projectId)

  if (updateError) {
    return { error: `Ошибка при обновлении проекта: ${updateError.message}` }
  }

  // Примечание: триггер auto_assign_project_owner_trigger автоматически добавляет
  // создателя проекта в project_members с ролью 'project_owner', поэтому
  // ручное добавление не требуется

  // Ревалидация пути
  revalidatePath('/dashboard')

  return { success: true }
}


'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import * as z from 'zod'

// Schema for upload source document
const uploadSourceSchema = z.object({
  projectId: z.string().uuid(),
  file: z.instanceof(File),
  docType: z.string().min(1, 'Document type is required'),
  templateId: z.string().uuid().optional(),
})

// Schema for create deliverable
const createDeliverableSchema = z.object({
  projectId: z.string().uuid(),
  templateId: z.string().uuid(),
  title: z.string().min(1, 'Title is required'),
})

/**
 * Upload source document to Supabase Storage and trigger Python API for parsing
 */
export async function uploadSourceAction(formData: FormData) {
  console.log('[uploadSourceAction] === НАЧАЛО ФУНКЦИИ ===')
  
  const supabase = await createClient()

  // Check authentication and refresh session to ensure JWT is available
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    console.error('[uploadSourceAction] Ошибка аутентификации:', authError)
    return { error: 'Необходима авторизация' }
  }
  
  console.log('[uploadSourceAction] Пользователь авторизован:', user.id)

  // Обновляем сессию, чтобы убедиться, что JWT токен доступен для RLS
  const {
    data: { session },
    error: sessionError,
  } = await supabase.auth.getSession()

  if (sessionError || !session) {
    return { error: 'Ошибка получения сессии. Пожалуйста, войдите заново.' }
  }

  // Extract form data
  const projectId = formData.get('projectId') as string
  const file = formData.get('file') as File
  const docType = formData.get('docType') as string
  const templateId = formData.get('templateId') as string | null
  
  console.log('[uploadSourceAction] Данные формы:', {
    projectId,
    fileName: file?.name,
    fileSize: file?.size,
    docType,
    templateId,
  })

  // Validate input
  const validationResult = uploadSourceSchema.safeParse({
    projectId,
    file,
    docType,
    templateId: templateId || undefined,
  })

  if (!validationResult.success) {
    return {
      error: validationResult.error.errors.map((e) => e.message).join(', '),
    }
  }

  const data = validationResult.data

  // Проверяем доступ к проекту перед загрузкой файла
  // Используем функцию has_project_access для проверки
  console.log('[uploadSourceAction] Проверка доступа к проекту...')
  const { data: projectAccess, error: accessError } = await supabase.rpc(
    'has_project_access',
    {
      proj_id: projectId,
      check_user_id: user.id,
    }
  )

  if (accessError) {
    console.error('[uploadSourceAction] Ошибка проверки доступа:', accessError)
    // Продолжаем выполнение, функция create_source_document тоже проверит доступ
  } else {
    console.log('[uploadSourceAction] Результат проверки доступа:', projectAccess)
  }

  if (projectAccess === false) {
    console.log('[uploadSourceAction] Доступ запрещен, возвращаем ошибку')
    return {
      error:
        'У вас нет доступа к этому проекту. Обратитесь к владельцу проекта для получения доступа. ' +
        'Убедитесь, что вы добавлены в таблицу project_members для этого проекта.',
    }
  }

  // Check file type (only PDF)
  console.log('[uploadSourceAction] Проверка типа файла:', file.type)
  if (file.type !== 'application/pdf') {
    console.log('[uploadSourceAction] Неверный тип файла')
    return { error: 'Поддерживаются только PDF файлы' }
  }

  // Check file size (max 50MB)
  const maxSize = 50 * 1024 * 1024 // 50MB
  console.log('[uploadSourceAction] Проверка размера файла:', file.size, 'max:', maxSize)
  if (file.size > maxSize) {
    console.log('[uploadSourceAction] Файл слишком большой')
    return { error: 'Размер файла не должен превышать 50MB' }
  }

  try {
    console.log('[uploadSourceAction] Начало загрузки файла в Storage...')
    // Generate unique file path
    const fileExt = file.name.split('.').pop()
    const fileName = `${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`
    const storagePath = `projects/${projectId}/sources/${fileName}`
    console.log('[uploadSourceAction] Путь для сохранения:', storagePath)

    // Upload file to Supabase Storage
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('documents')
      .upload(storagePath, file, {
        contentType: 'application/pdf',
        upsert: false,
      })

    if (uploadError) {
      console.error('[uploadSourceAction] Ошибка загрузки в Storage:', uploadError)
      return { error: `Ошибка при загрузке файла: ${uploadError.message}` }
    }
    
    console.log('[uploadSourceAction] Файл успешно загружен в Storage:', uploadData?.path)

    // Get public URL for the file
    const { data: urlData } = supabase.storage
      .from('documents')
      .getPublicUrl(storagePath)
    console.log('[uploadSourceAction] Public URL получен:', urlData?.publicUrl)

    // Create source_document record
    // Сначала пробуем использовать RPC функцию (если она существует), которая обходит проблему с auth.uid()
    console.log('[uploadSourceAction] Начало создания записи source_document...')
    let document: any = null
    let docError: any = null

    // Пробуем использовать RPC функцию create_source_document
    // Эта функция обходит проблему с auth.uid() возвращающим null
    console.log('[uploadSourceAction] Вызов create_source_document:', {
      projectId,
      userId: user.id,
      fileName: file.name,
      storagePath,
      docType,
    })
    
    const { data: documentId, error: rpcError } = await supabase.rpc(
      'create_source_document',
      {
        p_project_id: projectId,
        p_name: file.name,
        p_storage_path: storagePath,
        p_doc_type: docType,
        p_user_id: user.id,
      }
    )
    
    // Детальное логирование для диагностики (выводится в терминал сервера)
    if (rpcError) {
      console.error('[uploadSourceAction] Ошибка RPC create_source_document:', {
        message: rpcError.message,
        code: rpcError.code,
        details: rpcError.details,
        hint: rpcError.hint,
        fullError: rpcError,
      })
    } else {
      console.log('[uploadSourceAction] RPC успешно, documentId:', documentId)
    }

    if (!rpcError && documentId) {
      // RPC функция сработала, получаем созданный документ
      // Используем RPC функцию для получения, чтобы обойти RLS
      const { data: fetchedDoc, error: fetchError } = await supabase
        .from('source_documents')
        .select('*')
        .eq('id', documentId)
        .single()

      if (!fetchError && fetchedDoc) {
        document = fetchedDoc
      } else {
        // Если не удалось получить через SELECT (из-за RLS), 
        // создаем объект документа из ID
        if (fetchError?.message?.includes('row-level security')) {
          document = {
            id: documentId,
            project_id: projectId,
            name: file.name,
            storage_path: storagePath,
            doc_type: docType,
            status: 'uploading',
          }
        } else {
          docError = fetchError || new Error('Не удалось получить созданный документ')
        }
      }
    } else if (
      rpcError?.message?.includes('does not exist') ||
      rpcError?.code === '42883' ||
      rpcError?.message?.includes('function') && rpcError?.message?.includes('does not exist')
    ) {
      // RPC функция не существует, используем обычный INSERT
      // Это вызовет ошибку RLS, если auth.uid() возвращает null
      const { data: insertedDoc, error: insertError } = await supabase
        .from('source_documents')
        .insert({
          project_id: projectId,
          name: file.name,
          storage_path: storagePath,
          doc_type: docType,
          status: 'uploading',
        })
        .select()
        .single()

      if (insertError || !insertedDoc) {
        docError = insertError
      } else {
        document = insertedDoc
      }
    } else {
      // Другая ошибка от RPC функции
      // Проверяем конкретные типы ошибок
      console.error('[uploadSourceAction] Ошибка RPC функции (не обработана выше):', {
        message: rpcError?.message,
        code: rpcError?.code,
        details: rpcError?.details,
        hint: rpcError?.hint,
      })
      
      if (rpcError?.message?.includes('User does not have access')) {
        docError = {
          ...rpcError,
          message:
            'У вас нет доступа к этому проекту. Убедитесь, что вы добавлены в участники проекта (project_members).',
        }
      } else if (
        rpcError?.message?.includes('row-level security') ||
        rpcError?.message?.includes('violates row-level security') ||
        rpcError?.message?.includes('new row violates')
      ) {
        // Ошибка RLS даже при использовании SECURITY DEFINER функции
        // Это может означать, что функция не создана или не имеет прав
        console.error('[uploadSourceAction] RLS ошибка при вызове create_source_document:', rpcError)
        docError = {
          ...rpcError,
          message:
            'Ошибка доступа к базе данных при создании записи документа.\n\n' +
            'Возможные причины:\n' +
            '1. Функция create_source_document не создана в базе данных\n' +
            '2. Функция не имеет прав SECURITY DEFINER\n' +
            '3. Вы не добавлены в участники проекта (project_members)\n' +
            '4. Проблема с RLS политиками\n\n' +
            'Решение:\n' +
            '1. Выполните SQL скрипт schema_organizations_profiles_projects.sql в Supabase SQL Editor\n' +
            '2. Убедитесь, что вы добавлены в project_members для этого проекта\n' +
            '3. Проверьте логи сервера (терминал, где запущен Next.js) для деталей',
        }
      } else {
        docError = rpcError
      }
    }

    if (docError || !document) {
      // Try to delete uploaded file if document creation failed
      await supabase.storage.from('documents').remove([storagePath])

      // Более понятное сообщение для ошибок RLS
      let errorMessage = docError?.message || 'Неизвестная ошибка'
      
      // Детальное логирование для диагностики (выводится в терминал сервера)
      console.error('[uploadSourceAction] ОШИБКА создания документа:', {
        error: docError,
        errorMessage: docError?.message,
        errorCode: docError?.code,
        errorDetails: docError?.details,
        errorHint: docError?.hint,
        hasDocument: !!document,
        projectId,
        userId: user.id,
        fileName: file.name,
        storagePath,
      })
      
      // Если ошибка уже обработана выше (например, для RLS), используем её
      if (docError?.message && (
        docError.message.includes('row-level security') ||
        docError.message.includes('violates row-level security') ||
        docError.message.includes('create_source_document') ||
        docError.message.includes('project_members')
      )) {
        // Используем уже обработанное сообщение
        errorMessage = docError.message
      } else if (
        errorMessage.includes('row-level security') ||
        errorMessage.includes('violates row-level security') ||
        errorMessage.includes('new row violates') ||
        errorMessage.includes('auth.uid()')
      ) {
        errorMessage =
          'Ошибка доступа к базе данных при создании записи исходного документа.\n\n' +
          'Возможные причины:\n' +
          '1. Функция create_source_document не создана в базе данных\n' +
          '2. Вы не добавлены в участники проекта (project_members)\n' +
          '3. Проблема с аутентификацией (auth.uid() возвращает null)\n' +
          '4. Проблема с RLS политиками\n\n' +
          'Решение:\n' +
          '1. Выполните SQL скрипт schema_organizations_profiles_projects.sql в Supabase SQL Editor\n' +
          '2. Убедитесь, что вы добавлены в project_members для этого проекта\n' +
          '3. Проверьте логи в консоли браузера (F12) для деталей\n\n' +
          'Подробная инструкция: см. docs/RLS_ERROR_SOLUTION.md'
      } else if (errorMessage.includes('User does not have access')) {
        errorMessage =
          'У вас нет доступа к этому проекту. Обратитесь к владельцу проекта для получения доступа. ' +
          'Убедитесь, что вы добавлены в таблицу project_members для этого проекта.'
      }

      return {
        error: `Ошибка при загрузке файла: ${errorMessage}`,
      }
    }

    // Call Python API for parsing
    const aiEngineUrl = process.env.AI_ENGINE_URL || 'http://localhost:8000'
    const parseUrl = `${aiEngineUrl}/api/v1/parse`

    try {
      const parseResponse = await fetch(parseUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          document_id: document.id,
          file_path: storagePath,
          file_url: urlData.publicUrl,
          template_id: data.templateId || null,
        }),
      })

      if (!parseResponse.ok) {
        const errorText = await parseResponse.text()
        // Update document status to error
        await supabase
          .from('source_documents')
          .update({ status: 'error' })
          .eq('id', document.id)

        return {
          error: `Ошибка при запуске парсинга: ${errorText || 'Неизвестная ошибка'}`,
        }
      }
    } catch (apiError) {
      // Update document status to error
      await supabase
        .from('source_documents')
        .update({ status: 'error' })
        .eq('id', document.id)

      return {
        error: `Ошибка при вызове API парсинга: ${apiError instanceof Error ? apiError.message : 'Неизвестная ошибка'}`,
      }
    }

    // Revalidate project page
    revalidatePath(`/projects/${projectId}`)

    return { success: true, documentId: document.id }
  } catch (error) {
    return {
      error: `Неожиданная ошибка: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`,
    }
  }
}

/**
 * Create deliverable and automatically create empty deliverable_sections based on template
 */
export async function createDeliverableAction(formData: FormData) {
  const supabase = await createClient()

  // Check authentication
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { error: 'Необходима авторизация' }
  }

  // Extract form data
  const projectId = formData.get('projectId') as string
  const templateId = formData.get('templateId') as string
  const title = formData.get('title') as string

  // Validate input
  const validationResult = createDeliverableSchema.safeParse({
    projectId,
    templateId,
    title,
  })

  if (!validationResult.success) {
    return {
      error: validationResult.error.errors.map((e) => e.message).join(', '),
    }
  }

  const data = validationResult.data

  try {
    // Get all template sections for the selected template
    const { data: templateSections, error: sectionsError } = await supabase
      .from('template_sections')
      .select('id, title, section_number, parent_id, is_mandatory')
      .eq('template_id', data.templateId)
      .order('section_number', { ascending: true })

    if (sectionsError) {
      return {
        error: `Ошибка при получении секций шаблона: ${sectionsError.message}`,
      }
    }

    if (!templateSections || templateSections.length === 0) {
      return {
        error: 'Шаблон не содержит секций',
      }
    }

    // Create deliverable
    const { data: deliverable, error: deliverableError } = await supabase
      .from('deliverables')
      .insert({
        project_id: data.projectId,
        template_id: data.templateId,
        title: data.title,
        status: 'draft',
      })
      .select()
      .single()

    if (deliverableError || !deliverable) {
      return {
        error: `Ошибка при создании документа: ${deliverableError?.message || 'Неизвестная ошибка'}`,
      }
    }

    // Create deliverable_sections based on template_sections
    const deliverableSections = templateSections.map((section) => ({
      deliverable_id: deliverable.id,
      template_section_id: section.id,
      content_html: null,
      status: 'empty',
      used_source_section_ids: null,
    }))

    const { error: sectionsInsertError } = await supabase
      .from('deliverable_sections')
      .insert(deliverableSections)

    if (sectionsInsertError) {
      // Try to delete deliverable if sections creation failed
      await supabase.from('deliverables').delete().eq('id', deliverable.id)
      return {
        error: `Ошибка при создании секций: ${sectionsInsertError.message}`,
      }
    }

    // Revalidate project page
    revalidatePath(`/projects/${data.projectId}`)

    return { success: true, deliverableId: deliverable.id }
  } catch (error) {
    return {
      error: `Неожиданная ошибка: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`,
    }
  }
}

'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/types/database.types'

type IdealTemplate = Database['public']['Tables']['ideal_templates']['Row']
type IdealSection = Database['public']['Tables']['ideal_sections']['Row']
type IdealMapping = Database['public']['Tables']['ideal_mappings']['Row']

// Extended TreeNode type for internal use
type TreeNode = {
  id: string
  number: string
  title: string
  children: TreeNode[]
  orderIndex?: number
  parentId?: string | null
}

// Helper function to build tree from flat list
function buildTree(sections: IdealSection[]): TreeNode[] {
  const sectionMap = new Map<string, TreeNode>()
  const rootNodes: TreeNode[] = []

  // First pass: create all nodes
  sections.forEach((section) => {
    sectionMap.set(section.id, {
      id: section.id,
      number: '', // Will be calculated
      title: section.title,
      children: [],
      orderIndex: section.order_index,
      parentId: section.parent_id,
    })
  })

  // Helper to calculate section number recursively
  const calculateNumber = (node: TreeNode, parentNumber: string = ''): string => {
    if (!parentNumber) {
      // Root level - find index among root siblings
      const rootSiblings = Array.from(sectionMap.values())
        .filter((n) => !n.parentId)
        .sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0))
      const index = rootSiblings.findIndex((n) => n.id === node.id)
      return `${index + 1}`
    } else {
      // Child level
      const siblings = Array.from(sectionMap.values())
        .filter((n) => n.parentId === node.parentId)
        .sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0))
      const index = siblings.findIndex((n) => n.id === node.id)
      return `${parentNumber}.${index + 1}`
    }
  }

  // Build tree structure
  sections
    .sort((a, b) => a.order_index - b.order_index)
    .forEach((section) => {
      const node = sectionMap.get(section.id)!
      if (!section.parent_id) {
        node.number = calculateNumber(node)
        rootNodes.push(node)
      } else {
        const parent = sectionMap.get(section.parent_id)
        if (parent) {
          node.number = calculateNumber(node, parent.number || '')
          parent.children.push(node)
        }
      }
    })

  // Sort children recursively
  const sortChildren = (node: TreeNode) => {
    node.children.sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0))
    node.children.forEach(sortChildren)
  }

  rootNodes.forEach(sortChildren)
  return rootNodes.sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0))
}

/**
 * Fetch all ideal templates
 */
export async function getTemplates(): Promise<{ data: IdealTemplate[] | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  const { data, error } = await supabase
    .from('ideal_templates')
    .select('*')
    .order('name', { ascending: true })
    .order('version', { ascending: false })

  if (error) {
    return { data: null, error: error.message }
  }

  return { data, error: null }
}

/**
 * Fetch template structure (sections tree + mappings)
 */
export async function getTemplateStructure(
  templateId: string
): Promise<{ data: { tree: TreeNode[]; mappings: IdealMapping[] } | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  // Fetch all sections for this template
  const { data: sections, error: sectionsError } = await supabase
    .from('ideal_sections')
    .select('*')
    .eq('template_id', templateId)
    .order('order_index', { ascending: true })

  if (sectionsError) {
    return { data: null, error: sectionsError.message }
  }

  if (!sections || sections.length === 0) {
    return { data: { tree: [], mappings: [] }, error: null }
  }

  // Build tree from flat list
  const tree = buildTree(sections)

  // Fetch mappings for all sections in this template
  const sectionIds = sections.map((s) => s.id)
  const { data: mappings, error: mappingsError } = await supabase
    .from('ideal_mappings')
    .select('*')
    .in('target_ideal_section_id', sectionIds)
    .order('order_index', { ascending: true })

  if (mappingsError) {
    return { data: null, error: mappingsError.message }
  }

  // Fetch source sections and templates for mappings
  if (mappings && mappings.length > 0) {
    const sourceSectionIds = [...new Set(mappings.map((m) => m.source_ideal_section_id))]
    const { data: sourceSections } = await supabase
      .from('ideal_sections')
      .select('id, title, template_id')
      .in('id', sourceSectionIds)

    const templateIds = [...new Set(sourceSections?.map((s) => s.template_id) || [])]
    const { data: sourceTemplates } = await supabase
      .from('ideal_templates')
      .select('id, name')
      .in('id', templateIds)

    // Enrich mappings with source section and template info
    const templateMap = new Map(sourceTemplates?.map((t) => [t.id, t.name]) || [])
    const sectionMap = new Map(sourceSections?.map((s) => [s.id, s]) || [])

    const enrichedMappings = mappings.map((m) => {
      const sourceSection = sectionMap.get(m.source_ideal_section_id)
      const templateName = sourceSection ? templateMap.get(sourceSection.template_id) : 'Unknown'
      return {
        ...m,
        _sourceSectionTitle: sourceSection?.title || '',
        _sourceTemplateName: templateName || '',
      }
    })

    return { data: { tree, mappings: enrichedMappings }, error: null }
  }

  return { data: { tree, mappings: mappings || [] }, error: null }
}

/**
 * Create new ideal template
 */
export async function createTemplate(data: {
  name: string
  version: number
  isActive?: boolean
}): Promise<{ data: IdealTemplate | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  const { data: template, error } = await supabase
    .from('ideal_templates')
    .insert({
      name: data.name,
      version: data.version,
      is_active: data.isActive ?? true,
    })
    .select()
    .single()

  if (error) {
    return { data: null, error: error.message }
  }

  revalidatePath('/admin/templates')
  return { data: template, error: null }
}

/**
 * Create new section
 * Handles order_index logic: adds to end of siblings list
 */
export async function createSection(data: {
  templateId: string
  parentId?: string | null
  title: string
}): Promise<{ data: IdealSection | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  // Get max order_index for siblings (same parent)
  let siblingsQuery = supabase
    .from('ideal_sections')
    .select('order_index')
    .eq('template_id', data.templateId)
  
  if (data.parentId) {
    siblingsQuery = siblingsQuery.eq('parent_id', data.parentId)
  } else {
    siblingsQuery = siblingsQuery.is('parent_id', null)
  }
  
  const { data: siblings, error: siblingsError } = await siblingsQuery
    .order('order_index', { ascending: false })
    .limit(1)

  if (siblingsError) {
    return { data: null, error: siblingsError.message }
  }

  const maxOrderIndex = siblings && siblings.length > 0 ? siblings[0].order_index : -1
  const newOrderIndex = maxOrderIndex + 1

  const insertData: {
    template_id: string
    parent_id?: string | null
    title: string
    order_index: number
  } = {
    template_id: data.templateId,
    title: data.title,
    order_index: newOrderIndex,
  }
  
  if (data.parentId) {
    insertData.parent_id = data.parentId
  } else {
    insertData.parent_id = null
  }
  
  const { data: section, error } = await supabase
    .from('ideal_sections')
    .insert(insertData)
    .select()
    .single()

  if (error) {
    return { data: null, error: error.message }
  }

  revalidatePath('/admin/templates')
  return { data: section, error: null }
}

/**
 * Update section (title only for now, can be extended)
 */
export async function updateSection(
  id: string,
  data: { title?: string }
): Promise<{ data: IdealSection | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  const updateData: Partial<IdealSection> = {}
  if (data.title !== undefined) {
    updateData.title = data.title
  }

  const { data: section, error } = await supabase
    .from('ideal_sections')
    .update(updateData)
    .eq('id', id)
    .select()
    .single()

  if (error) {
    return { data: null, error: error.message }
  }

  revalidatePath('/admin/templates')
  return { data: section, error: null }
}

/**
 * Delete section
 * Prevents deletion if children exist
 */
export async function deleteSection(id: string): Promise<{ success: boolean; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { success: false, error: 'Необходима авторизация' }
  }

  // Check if section has children
  const { data: children, error: childrenError } = await supabase
    .from('ideal_sections')
    .select('id')
    .eq('parent_id', id)
    .limit(1)

  if (childrenError) {
    return { success: false, error: childrenError.message }
  }

  if (children && children.length > 0) {
    return { success: false, error: 'Нельзя удалить секцию, у которой есть дочерние секции' }
  }

  const { error } = await supabase.from('ideal_sections').delete().eq('id', id)

  if (error) {
    return { success: false, error: error.message }
  }

  revalidatePath('/admin/templates')
  return { success: true, error: null }
}

/**
 * Save mapping (insert or update)
 */
export async function saveMapping(data: {
  id?: string
  targetSectionId: string
  sourceSectionId: string
  instruction: string
  orderIndex?: number
}): Promise<{ data: IdealMapping | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  // If updating existing mapping
  if (data.id) {
    const { data: mapping, error } = await supabase
      .from('ideal_mappings')
      .update({
        source_ideal_section_id: data.sourceSectionId,
        instruction: data.instruction,
        order_index: data.orderIndex ?? 0,
      })
      .eq('id', data.id)
      .select()
      .single()

    if (error) {
      return { data: null, error: error.message }
    }

    revalidatePath('/admin/templates')
    return { data: mapping, error: null }
  }

  // If creating new mapping, get max order_index for target section
  const { data: existingMappings, error: existingError } = await supabase
    .from('ideal_mappings')
    .select('order_index')
    .eq('target_ideal_section_id', data.targetSectionId)
    .order('order_index', { ascending: false })
    .limit(1)

  if (existingError) {
    return { data: null, error: existingError.message }
  }

  const maxOrderIndex = existingMappings && existingMappings.length > 0 ? existingMappings[0].order_index : -1
  const newOrderIndex = data.orderIndex ?? maxOrderIndex + 1

  const { data: mapping, error } = await supabase
    .from('ideal_mappings')
    .insert({
      target_ideal_section_id: data.targetSectionId,
      source_ideal_section_id: data.sourceSectionId,
      instruction: data.instruction,
      order_index: newOrderIndex,
    })
    .select()
    .single()

  if (error) {
    return { data: null, error: error.message }
  }

  revalidatePath('/admin/templates')
  return { data: mapping, error: null }
}

/**
 * Reorder section: Move Up/Down (swap with neighbor) or Indent/Outdent (change parent)
 */
export async function reorderSection(
  id: string,
  action: 'moveUp' | 'moveDown' | 'indent' | 'outdent'
): Promise<{ success: boolean; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { success: false, error: 'Необходима авторизация' }
  }

  // Get current section
  const { data: section, error: sectionError } = await supabase
    .from('ideal_sections')
    .select('*')
    .eq('id', id)
    .single()

  if (sectionError || !section) {
    return { success: false, error: sectionError?.message || 'Секция не найдена' }
  }

  // Get all siblings (same parent)
  let siblingsQuery = supabase
    .from('ideal_sections')
    .select('*')
    .eq('template_id', section.template_id)
  
  if (section.parent_id) {
    siblingsQuery = siblingsQuery.eq('parent_id', section.parent_id)
  } else {
    siblingsQuery = siblingsQuery.is('parent_id', null)
  }
  
  const { data: siblings, error: siblingsError } = await siblingsQuery
    .order('order_index', { ascending: true })

  if (siblingsError) {
    return { success: false, error: siblingsError.message }
  }

  if (!siblings || siblings.length === 0) {
    return { success: false, error: 'Не найдены соседние секции' }
  }

  const currentIndex = siblings.findIndex((s) => s.id === id)

  if (action === 'moveUp') {
    if (currentIndex === 0) {
      return { success: false, error: 'Секция уже в начале списка' }
    }

    const prevSection = siblings[currentIndex - 1]
    // Swap order_index
    const tempOrder = section.order_index
    await supabase
      .from('ideal_sections')
      .update({ order_index: prevSection.order_index })
      .eq('id', id)
    await supabase
      .from('ideal_sections')
      .update({ order_index: tempOrder })
      .eq('id', prevSection.id)
  } else if (action === 'moveDown') {
    if (currentIndex === siblings.length - 1) {
      return { success: false, error: 'Секция уже в конце списка' }
    }

    const nextSection = siblings[currentIndex + 1]
    // Swap order_index
    const tempOrder = section.order_index
    await supabase
      .from('ideal_sections')
      .update({ order_index: nextSection.order_index })
      .eq('id', id)
    await supabase
      .from('ideal_sections')
      .update({ order_index: tempOrder })
      .eq('id', nextSection.id)
  } else if (action === 'indent') {
    // Make this section a child of the previous sibling
    if (currentIndex === 0) {
      return { success: false, error: 'Нельзя сделать отступ для первой секции' }
    }

    const newParent = siblings[currentIndex - 1]
    // Get max order_index for children of new parent
    const { data: children, error: childrenError } = await supabase
      .from('ideal_sections')
      .select('order_index')
      .eq('parent_id', newParent.id)
      .order('order_index', { ascending: false })
      .limit(1)

    if (childrenError) {
      return { success: false, error: childrenError.message }
    }

    const maxChildOrder = children && children.length > 0 ? children[0].order_index : -1
    const newOrderIndex = maxChildOrder + 1

    // Update section: change parent and order_index
    const { error: updateError } = await supabase
      .from('ideal_sections')
      .update({
        parent_id: newParent.id,
        order_index: newOrderIndex,
      })
      .eq('id', id)

    if (updateError) {
      return { success: false, error: updateError.message }
    }

    // Shift remaining siblings' order_index down by 1
    const remainingSiblings = siblings.slice(currentIndex + 1)
    for (const sibling of remainingSiblings) {
      await supabase
        .from('ideal_sections')
        .update({ order_index: sibling.order_index - 1 })
        .eq('id', sibling.id)
    }
  } else if (action === 'outdent') {
    // Make this section a sibling of its parent
    if (!section.parent_id) {
      return { success: false, error: 'Секция уже на верхнем уровне' }
    }

    // Get parent section
    const { data: parent, error: parentError } = await supabase
      .from('ideal_sections')
      .select('*')
      .eq('id', section.parent_id)
      .single()

    if (parentError || !parent) {
      return { success: false, error: parentError?.message || 'Родительская секция не найдена' }
    }

    // Get parent's siblings
    let parentSiblingsQuery = supabase
      .from('ideal_sections')
      .select('*')
      .eq('template_id', section.template_id)
    
    if (parent.parent_id) {
      parentSiblingsQuery = parentSiblingsQuery.eq('parent_id', parent.parent_id)
    } else {
      parentSiblingsQuery = parentSiblingsQuery.is('parent_id', null)
    }
    
    const { data: parentSiblings, error: parentSiblingsError } = await parentSiblingsQuery
      .order('order_index', { ascending: true })

    if (parentSiblingsError) {
      return { success: false, error: parentSiblingsError.message }
    }

    // Find parent's index and place section after it
    const parentIndex = parentSiblings?.findIndex((s) => s.id === parent.id) ?? -1
    const insertAfterIndex = parentIndex
    const newOrderIndex =
      insertAfterIndex >= 0 && parentSiblings
        ? parentSiblings[insertAfterIndex].order_index + 1
        : (parent.order_index || 0) + 1

    // Shift siblings after insert position
    if (parentSiblings) {
      for (const sibling of parentSiblings) {
        if (sibling.order_index >= newOrderIndex) {
          await supabase
            .from('ideal_sections')
            .update({ order_index: sibling.order_index + 1 })
            .eq('id', sibling.id)
        }
      }
    }

    // Update section: change parent and order_index
    const updateData: {
      parent_id: string | null
      order_index: number
    } = {
      parent_id: parent.parent_id || null,
      order_index: newOrderIndex,
    }
    
    const { error: updateError } = await supabase
      .from('ideal_sections')
      .update(updateData)
      .eq('id', id)

    if (updateError) {
      return { success: false, error: updateError.message }
    }
  }

  revalidatePath('/admin/templates')
  return { success: true, error: null }
}

/**
 * Search sections from other templates (for mapping)
 */
export async function searchSections(
  templateId: string,
  query?: string
): Promise<{ data: IdealSection[] | null; error: string | null }> {
  const supabase = await createClient()

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { data: null, error: 'Необходима авторизация' }
  }

  let queryBuilder = supabase
    .from('ideal_sections')
    .select('*')
    .neq('template_id', templateId) // Exclude current template
    .order('title', { ascending: true })

  if (query) {
    queryBuilder = queryBuilder.ilike('title', `%${query}%`)
  }

  const { data, error } = await queryBuilder.limit(50)

  if (error) {
    return { data: null, error: error.message }
  }

  return { data, error: null }
}

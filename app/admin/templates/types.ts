export type Template = {
  id: string
  name: string
  version: number
  is_active: boolean
  group_id?: string | null
  created_at: string
  updated_at: string
}

// UI-friendly template with computed status
export type TemplateUI = {
  id: string
  name: string
  version: string // Formatted as "v1.0"
  status: "Active" | "Draft"
}

export type TreeNode = {
  id: string
  number: string
  title: string
  children: TreeNode[]
  description?: string // Not in DB yet, but used in UI
  isMandatory?: boolean // Not in DB yet, but used in UI
  mappings?: Mapping[]
  orderIndex?: number
  parentId?: string | null
}

export type Mapping = {
  id: string
  sourceTemplate: string // Template name (computed)
  sourceSection: string // Section title (computed)
  sourceSectionId: string
  instruction: string
  order: number // order_index from DB
}

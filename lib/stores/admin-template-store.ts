import { create } from 'zustand'
import type { Template, TemplateUI, TreeNode, Mapping } from '@/app/admin/templates/types'

interface AdminTemplateStore {
  // Templates (DB format)
  templates: Template[]
  selectedTemplateId: string | null

  // Tree structure
  tree: TreeNode | null
  selectedNodeId: string | null

  // Mappings
  mappings: Record<string, Mapping[]> // sectionId -> mappings[]

  // Actions
  setTemplates: (templates: Template[]) => void
  selectTemplate: (templateId: string) => void
  setTree: (tree: TreeNode | null) => void
  selectNode: (nodeId: string | null) => void
  addNode: (node: TreeNode, parentId?: string | null) => void
  updateNode: (nodeId: string, updates: Partial<TreeNode>) => void
  removeNode: (nodeId: string) => void
  setMappings: (sectionId: string, mappings: Mapping[]) => void
  addMapping: (sectionId: string, mapping: Mapping) => void
  removeMapping: (sectionId: string, mappingId: string) => void

  // Helper: find node in tree
  findNode: (nodeId: string, root?: TreeNode) => TreeNode | null

  // Helper: update node in tree recursively
  updateNodeInTree: (nodeId: string, updates: Partial<TreeNode>, root?: TreeNode) => TreeNode | null
}

export const useAdminTemplateStore = create<AdminTemplateStore>((set, get) => ({
  templates: [],
  selectedTemplateId: null,
  tree: null,
  selectedNodeId: null,
  mappings: {},

  setTemplates: (templates) => set({ templates }),

  selectTemplate: (templateId) => set({ selectedTemplateId: templateId, selectedNodeId: null, tree: null, mappings: {} }),

  setTree: (tree) => set({ tree, selectedNodeId: null }),

  selectNode: (nodeId) => set({ selectedNodeId: nodeId }),

  findNode: (nodeId, root) => {
    const tree = root || get().tree
    if (!tree) return null

    if (tree.id === nodeId) return tree

    for (const child of tree.children) {
      const found = get().findNode(nodeId, child)
      if (found) return found
    }

    return null
  },

  updateNodeInTree: (nodeId, updates, root) => {
    const tree = root || get().tree
    if (!tree) return null

    if (tree.id === nodeId) {
      return { ...tree, ...updates }
    }

    const updatedChildren = tree.children.map((child) => {
      const updated = get().updateNodeInTree(nodeId, updates, child)
      return updated || child
    })

    return { ...tree, children: updatedChildren }
  },

  addNode: (node, parentId) => {
    const tree = get().tree
    if (!tree) {
      // If no tree, set as root
      set({ tree: node })
      return
    }

    if (!parentId) {
      // Add as root level child
      const updatedTree = {
        ...tree,
        children: [...tree.children, node],
      }
      set({ tree: updatedTree })
      return
    }

    // Find parent and add node
    const parent = get().findNode(parentId)
    if (!parent) return

    const updatedTree = get().updateNodeInTree(parentId, {
      children: [...parent.children, node],
    })

    if (updatedTree) {
      set({ tree: updatedTree })
    }
  },

  updateNode: (nodeId, updates) => {
    const updatedTree = get().updateNodeInTree(nodeId, updates)
    if (updatedTree) {
      set({ tree: updatedTree })
    }
  },

  removeNode: (nodeId) => {
    const tree = get().tree
    if (!tree) return

    // If removing root, clear tree
    if (tree.id === nodeId) {
      set({ tree: null, selectedNodeId: null })
      return
    }

    // Helper to remove node from children
    const removeFromChildren = (node: TreeNode): TreeNode => {
      return {
        ...node,
        children: node.children
          .filter((child) => child.id !== nodeId)
          .map(removeFromChildren),
      }
    }

    const updatedTree = removeFromChildren(tree)
    set({ tree: updatedTree, selectedNodeId: get().selectedNodeId === nodeId ? null : get().selectedNodeId })
  },

  setMappings: (sectionId, mappings) =>
    set((state) => ({
      mappings: {
        ...state.mappings,
        [sectionId]: mappings,
      },
    })),

  addMapping: (sectionId, mapping) =>
    set((state) => ({
      mappings: {
        ...state.mappings,
        [sectionId]: [...(state.mappings[sectionId] || []), mapping],
      },
    })),

  removeMapping: (sectionId, mappingId) =>
    set((state) => ({
      mappings: {
        ...state.mappings,
        [sectionId]: (state.mappings[sectionId] || []).filter((m) => m.id !== mappingId),
      },
    })),
}))

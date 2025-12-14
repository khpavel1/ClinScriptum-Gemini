"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Checkbox } from "@/components/ui/checkbox"
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "@/components/ui/resizable"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { TemplatesSidebar } from "./_components/templates-sidebar"
import { StructureTree } from "./_components/structure-tree"
import { SectionInspector } from "./_components/section-inspector"
import { useAdminTemplateStore } from "@/lib/stores/admin-template-store"
import {
  getTemplates,
  getTemplateStructure,
  createTemplate,
  createSection,
  updateSection,
  deleteSection,
  saveMapping,
  reorderSection,
  searchSections,
} from "./actions"
import type { Template, TemplateUI, TreeNode, Mapping } from "./types"

// Helper to convert DB template to UI template
function templateToUI(template: Template): TemplateUI {
  return {
    id: template.id,
    name: template.name,
    version: `v${template.version}`,
    status: template.is_active ? "Active" : "Draft",
  }
}

export default function IdealTemplateManager() {
  const store = useAdminTemplateStore()
  const [templatesUI, setTemplatesUI] = useState<TemplateUI[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [isNewTemplateDialogOpen, setIsNewTemplateDialogOpen] = useState(false)
  const [newTemplateName, setNewTemplateName] = useState("")
  const [newTemplateVersion, setNewTemplateVersion] = useState("1")
  const [newTemplateStatus, setNewTemplateStatus] = useState<"Active" | "Draft">("Draft")
  const [isNewSectionDialogOpen, setIsNewSectionDialogOpen] = useState(false)
  const [newSectionTitle, setNewSectionTitle] = useState("")
  const [newSectionDescription, setNewSectionDescription] = useState("")
  const [newSectionIsMandatory, setNewSectionIsMandatory] = useState(false)
  const [isAddMappingOpen, setIsAddMappingOpen] = useState(false)
  const [newMapping, setNewMapping] = useState({
    sourceTemplateId: "",
    sourceSectionId: "",
    instruction: "",
  })
  const [availableSections, setAvailableSections] = useState<Array<{ id: string; title: string; templateName: string }>>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Load templates on mount
  useEffect(() => {
    loadTemplates()
  }, [])

  // Load template structure when template is selected
  useEffect(() => {
    if (store.selectedTemplateId) {
      loadTemplateStructure(store.selectedTemplateId)
    }
  }, [store.selectedTemplateId])

  // Load available sections for mapping when dialog opens
  useEffect(() => {
    if (isAddMappingOpen && store.selectedTemplateId) {
      loadAvailableSections(store.selectedTemplateId)
    }
  }, [isAddMappingOpen, store.selectedTemplateId])

  async function loadTemplates() {
    setIsLoading(true)
    setError(null)
    const { data, error: err } = await getTemplates()
    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }
    if (data) {
      store.setTemplates(data)
      setTemplatesUI(data.map(templateToUI))
      if (data.length > 0 && !store.selectedTemplateId) {
        store.selectTemplate(data[0].id)
      }
    }
    setIsLoading(false)
  }

  async function loadTemplateStructure(templateId: string) {
    setIsLoading(true)
    setError(null)
    const { data, error: err } = await getTemplateStructure(templateId)
    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }
    if (data) {
      // Convert flat tree array to single root node (or create root if empty)
      if (data.tree.length === 0) {
        store.setTree(null)
      } else if (data.tree.length === 1) {
        store.setTree(data.tree[0])
      } else {
        // Multiple root nodes - create a virtual root
        store.setTree({
          id: `root-${templateId}`,
          number: "",
          title: "Root",
          children: data.tree,
        })
      }

      // Load mappings into store
      const mappingsBySection: Record<string, Mapping[]> = {}
      for (const mapping of data.mappings) {
        if (!mappingsBySection[mapping.target_ideal_section_id]) {
          mappingsBySection[mapping.target_ideal_section_id] = []
        }
        // Use enriched mapping data
        const enrichedMapping = mapping as any
        mappingsBySection[mapping.target_ideal_section_id].push({
          id: mapping.id,
          sourceTemplate: enrichedMapping._sourceTemplateName || "",
          sourceSection: enrichedMapping._sourceSectionTitle || "",
          sourceSectionId: mapping.source_ideal_section_id,
          instruction: mapping.instruction || "",
          order: mapping.order_index,
        })
      }
      Object.entries(mappingsBySection).forEach(([sectionId, mappings]) => {
        store.setMappings(sectionId, mappings)
      })
    }
    setIsLoading(false)
  }

  async function loadAvailableSections(templateId: string) {
    const { data, error: err } = await searchSections(templateId)
    if (err || !data) return

    // Fetch template names for sections
    const templateIds = [...new Set(data.map((s) => s.template_id))]
    const { data: templates } = await getTemplates()
    const templateMap = new Map(templates?.map((t) => [t.id, t.name]) || [])

    setAvailableSections(
      data.map((section) => ({
        id: section.id,
        title: section.title,
        templateName: templateMap.get(section.template_id) || "Unknown",
      }))
    )
  }

  const handleCreateTemplate = async () => {
    if (!newTemplateName.trim()) return

    setIsLoading(true)
    setError(null)
    const version = parseInt(newTemplateVersion) || 1
    const { data, error: err } = await createTemplate({
      name: newTemplateName,
      version,
      isActive: newTemplateStatus === "Active",
    })

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (data) {
      await loadTemplates()
      store.selectTemplate(data.id)
    }

    setIsNewTemplateDialogOpen(false)
    setNewTemplateName("")
    setNewTemplateVersion("1")
    setNewTemplateStatus("Draft")
    setIsLoading(false)
  }

  const handleCreateSection = async () => {
    if (!newSectionTitle.trim() || !store.selectedTemplateId) return

    setIsLoading(true)
    setError(null)
    const selectedNode = store.selectedNodeId ? store.findNode(store.selectedNodeId) : null
    const parentId = selectedNode?.id !== `root-${store.selectedTemplateId}` ? selectedNode?.id : undefined

    const { data, error: err } = await createSection({
      templateId: store.selectedTemplateId,
      parentId: parentId ?? null,
      title: newSectionTitle,
    })

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (data) {
      await loadTemplateStructure(store.selectedTemplateId)
    }

    setIsNewSectionDialogOpen(false)
    setNewSectionTitle("")
    setNewSectionDescription("")
    setNewSectionIsMandatory(false)
    setIsLoading(false)
  }

  const handleCreateMapping = async () => {
    if (!newMapping.sourceSectionId || !newMapping.instruction.trim() || !store.selectedNodeId) return

    setIsLoading(true)
    setError(null)
    const { data, error: err } = await saveMapping({
      targetSectionId: store.selectedNodeId,
      sourceSectionId: newMapping.sourceSectionId,
      instruction: newMapping.instruction,
    })

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (data) {
      await loadTemplateStructure(store.selectedTemplateId!)
      // Reload mappings for selected section
      const sectionMappings = store.mappings[store.selectedNodeId] || []
      const sourceSection = availableSections.find((s) => s.id === newMapping.sourceSectionId)
      if (sourceSection) {
        store.addMapping(store.selectedNodeId, {
          id: data.id,
          sourceTemplate: sourceSection.templateName,
          sourceSection: sourceSection.title,
          sourceSectionId: data.source_ideal_section_id,
          instruction: data.instruction || "",
          order: data.order_index,
        })
      }
    }

    setIsAddMappingOpen(false)
    setNewMapping({ sourceTemplateId: "", sourceSectionId: "", instruction: "" })
    setIsLoading(false)
  }

  const handleSelectSection = (section: TreeNode) => {
    store.selectNode(section.id)
  }

  const handleUpdateSection = async (updates: { title?: string; description?: string; isMandatory?: boolean }) => {
    if (!store.selectedNodeId) return

    setIsLoading(true)
    setError(null)
    const { data, error: err } = await updateSection(store.selectedNodeId, {
      title: updates.title,
    })

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (data) {
      store.updateNode(store.selectedNodeId, { title: data.title })
      await loadTemplateStructure(store.selectedTemplateId!)
    }

    setIsLoading(false)
  }

  const handleDeleteSection = async () => {
    if (!store.selectedNodeId) return

    if (!confirm("Вы уверены, что хотите удалить эту секцию?")) return

    setIsLoading(true)
    setError(null)
    const { success, error: err } = await deleteSection(store.selectedNodeId)

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (success) {
      store.removeNode(store.selectedNodeId)
      await loadTemplateStructure(store.selectedTemplateId!)
    }

    setIsLoading(false)
  }

  const handleReorderSection = async (action: "moveUp" | "moveDown" | "indent" | "outdent") => {
    if (!store.selectedNodeId) return

    setIsLoading(true)
    setError(null)
    const { success, error: err } = await reorderSection(store.selectedNodeId, action)

    if (err) {
      setError(err)
      setIsLoading(false)
      return
    }

    if (success) {
      await loadTemplateStructure(store.selectedTemplateId!)
    }

    setIsLoading(false)
  }

  const selectedTemplateUI = templatesUI.find((t) => t.id === store.selectedTemplateId)
  const selectedNode = store.selectedNodeId ? store.findNode(store.selectedNodeId) : null
  const selectedMappings = store.selectedNodeId ? store.mappings[store.selectedNodeId] || [] : []

  return (
    <div className="flex flex-col h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-card px-6 py-3 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Ideal Template Manager</h1>
          <p className="text-xs text-muted-foreground">Medical Documentation System</p>
        </div>
        {error && (
          <div className="px-3 py-1.5 bg-destructive/10 text-destructive text-xs rounded">
            {error}
          </div>
        )}
      </header>

      {/* Main Content */}
      <ResizablePanelGroup direction="horizontal" className="flex-1">
        {/* Panel 1: Templates List */}
        <ResizablePanel defaultSize={20} minSize={15}>
          <TemplatesSidebar
            templates={templatesUI}
            selectedTemplateId={store.selectedTemplateId || ""}
            onSelect={(template) => store.selectTemplate(template.id)}
            onAddNew={() => setIsNewTemplateDialogOpen(true)}
            searchQuery={searchQuery}
            onSearchChange={setSearchQuery}
          />
        </ResizablePanel>

        <ResizableHandle withHandle />

        {/* Panel 2: Structure Tree Editor */}
        <ResizablePanel defaultSize={40} minSize={30}>
          <StructureTree
            sections={store.tree}
            selectedSectionId={store.selectedNodeId}
            onSelectSection={handleSelectSection}
            onAddSection={() => setIsNewSectionDialogOpen(true)}
            onDeleteSection={handleDeleteSection}
            onReorderSection={handleReorderSection}
            templateName={selectedTemplateUI?.name || ""}
          />
        </ResizablePanel>

        <ResizableHandle withHandle />

        {/* Panel 3: Section Inspector & Mappings */}
        <ResizablePanel defaultSize={40} minSize={30}>
          <SectionInspector
            selectedSection={selectedNode}
            onUpdate={handleUpdateSection}
            mappings={selectedMappings}
            onAddMapping={() => setIsAddMappingOpen(true)}
          />
        </ResizablePanel>
      </ResizablePanelGroup>

      {/* New Template Dialog */}
      <Dialog open={isNewTemplateDialogOpen} onOpenChange={setIsNewTemplateDialogOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>Add New Template</DialogTitle>
            <DialogDescription className="text-xs">
              Create a new document template for medical documentation.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="template-name" className="text-xs font-medium">
                Template Name
              </Label>
              <Input
                id="template-name"
                placeholder="e.g., Clinical Study Report"
                className="h-9 text-sm"
                value={newTemplateName}
                onChange={(e) => setNewTemplateName(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="template-version" className="text-xs font-medium">
                Version
              </Label>
              <Input
                id="template-version"
                placeholder="1"
                type="number"
                min="1"
                className="h-9 text-sm"
                value={newTemplateVersion}
                onChange={(e) => setNewTemplateVersion(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="template-status" className="text-xs font-medium">
                Status
              </Label>
              <Select
                value={newTemplateStatus}
                onValueChange={(value: "Active" | "Draft") => setNewTemplateStatus(value)}
              >
                <SelectTrigger className="h-9 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Draft">Draft</SelectItem>
                  <SelectItem value="Active">Active</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsNewTemplateDialogOpen(false)} className="text-xs">
              Cancel
            </Button>
            <Button
              onClick={handleCreateTemplate}
              disabled={!newTemplateName.trim() || isLoading}
              className="text-xs"
            >
              {isLoading ? "Создание..." : "Create Template"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* New Section Dialog */}
      <Dialog open={isNewSectionDialogOpen} onOpenChange={setIsNewSectionDialogOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>Add New Section</DialogTitle>
            <DialogDescription className="text-xs">Create a new section in the document structure.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="section-title" className="text-xs font-medium">
                Section Title
              </Label>
              <Input
                id="section-title"
                placeholder="e.g., Study Objectives"
                className="h-9 text-sm"
                value={newSectionTitle}
                onChange={(e) => setNewSectionTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="section-description" className="text-xs font-medium">
                Description / Context for AI
              </Label>
              <Textarea
                id="section-description"
                placeholder="Provide context for AI generation..."
                className="min-h-[100px] text-sm"
                value={newSectionDescription}
                onChange={(e) => setNewSectionDescription(e.target.value)}
              />
            </div>
            <div className="flex items-center space-x-2">
              <Checkbox
                id="new-section-mandatory"
                checked={newSectionIsMandatory}
                onCheckedChange={(checked) => setNewSectionIsMandatory(checked as boolean)}
              />
              <Label htmlFor="new-section-mandatory" className="text-xs font-normal cursor-pointer">
                Is Mandatory?
              </Label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsNewSectionDialogOpen(false)} className="text-xs">
              Cancel
            </Button>
            <Button
              onClick={handleCreateSection}
              disabled={!newSectionTitle.trim() || isLoading || !store.selectedTemplateId}
              className="text-xs"
            >
              {isLoading ? "Создание..." : "Create Section"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Add Mapping Dialog */}
      <Dialog open={isAddMappingOpen} onOpenChange={setIsAddMappingOpen}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>Add Source Mapping</DialogTitle>
            <DialogDescription>Map content from another template section to this section</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <label className="text-sm font-medium">Source Section</label>
              <select
                value={newMapping.sourceSectionId}
                onChange={(e) => setNewMapping({ ...newMapping, sourceSectionId: e.target.value })}
                className="w-full h-9 px-3 rounded-md border border-input bg-background text-sm"
              >
                <option value="">Select section...</option>
                {availableSections.map((section) => (
                  <option key={section.id} value={section.id}>
                    [{section.templateName}] {section.title}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-2">
              <label className="text-sm font-medium">AI Prompt Instructions</label>
              <Textarea
                value={newMapping.instruction}
                onChange={(e) => setNewMapping({ ...newMapping, instruction: e.target.value })}
                placeholder="Describe how the AI should process and map content from the source section..."
                className="min-h-[120px] text-sm"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsAddMappingOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleCreateMapping}
              disabled={!newMapping.sourceSectionId || !newMapping.instruction.trim() || isLoading}
            >
              {isLoading ? "Создание..." : "Create Mapping"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

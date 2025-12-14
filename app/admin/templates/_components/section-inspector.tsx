"use client"

import { useState, useEffect } from "react"
import { Plus, MoreVertical } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Checkbox } from "@/components/ui/checkbox"
import type { TreeNode, Mapping } from "../types"

interface SectionInspectorProps {
  selectedSection: TreeNode | null
  onUpdate: (updates: { title?: string; description?: string; isMandatory?: boolean }) => void
  mappings?: Mapping[]
  onAddMapping?: () => void
}

export function SectionInspector({ selectedSection, onUpdate, mappings = [], onAddMapping }: SectionInspectorProps) {
  const [activeTab, setActiveTab] = useState<"general" | "mappings">("general")
  const [editedSectionTitle, setEditedSectionTitle] = useState(selectedSection?.title || "")
  const [editedSectionDescription, setEditedSectionDescription] = useState(selectedSection?.description || "")
  const [editedSectionMandatory, setEditedSectionMandatory] = useState(selectedSection?.isMandatory || false)

  // Update local state when selectedSection changes
  useEffect(() => {
    if (selectedSection) {
      setEditedSectionTitle(selectedSection.title)
      setEditedSectionDescription(selectedSection.description || "")
      setEditedSectionMandatory(selectedSection.isMandatory || false)
    }
  }, [selectedSection])

  const handleTitleChange = (value: string) => {
    setEditedSectionTitle(value)
    onUpdate({ title: value })
  }

  const handleDescriptionChange = (value: string) => {
    setEditedSectionDescription(value)
    onUpdate({ description: value })
  }

  const handleMandatoryChange = (checked: boolean) => {
    setEditedSectionMandatory(checked)
    onUpdate({ isMandatory: checked })
  }

  if (!selectedSection) {
    return (
      <div className="h-full flex flex-col bg-card border-l">
        <div className="flex items-center justify-center h-full">
          <div className="text-center">
            <p className="text-sm text-muted-foreground">No section selected</p>
            <p className="text-xs text-muted-foreground mt-1">Select a section from the tree to view details</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col bg-card border-l">
      <div className="border-b">
        <div className="flex border-b">
          <button
            onClick={() => setActiveTab("general")}
            className={`px-4 py-2.5 text-xs font-medium transition-colors border-b-2 ${
              activeTab === "general"
                ? "border-primary text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            General
          </button>
          <button
            onClick={() => setActiveTab("mappings")}
            className={`px-4 py-2.5 text-xs font-medium transition-colors border-b-2 ${
              activeTab === "mappings"
                ? "border-primary text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground"
            }`}
          >
            AI Mappings
          </button>
        </div>
      </div>
      <div className="flex-1 overflow-auto p-4">
        {activeTab === "general" ? (
          <div className="space-y-4">
            <div className="space-y-2">
              <Label className="text-xs font-medium">Section Number</Label>
              <Input value={selectedSection.number} readOnly className="h-9 text-sm bg-muted" />
            </div>
            <div className="space-y-2">
              <Label className="text-xs font-medium">Section Title</Label>
              <Input
                value={editedSectionTitle}
                onChange={(e) => handleTitleChange(e.target.value)}
                placeholder="Enter section title"
                className="h-9 text-sm"
              />
            </div>
            <div className="space-y-2">
              <Label className="text-xs font-medium">Description / Context for AI</Label>
              <Textarea
                value={editedSectionDescription}
                onChange={(e) => handleDescriptionChange(e.target.value)}
                placeholder="Provide context for AI generation..."
                className="min-h-[120px] text-sm"
              />
            </div>
            <div className="flex items-center space-x-2">
              <Checkbox
                id="mandatory"
                checked={editedSectionMandatory}
                onCheckedChange={(checked) => handleMandatoryChange(checked as boolean)}
              />
              <Label htmlFor="mandatory" className="text-xs font-normal cursor-pointer">
                Is Mandatory?
              </Label>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold">Source Mappings</h3>
              {onAddMapping && (
                <Button size="sm" className="h-7 text-xs" onClick={onAddMapping}>
                  <Plus className="h-3.5 w-3.5 mr-1" />
                  Add Mapping
                </Button>
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              Define how content from other templates should be mapped to this section.
            </p>
            <div className="space-y-2">
              {mappings && mappings.length > 0 ? (
                mappings.map((mapping) => (
                  <div key={mapping.id} className="p-3 rounded-lg border bg-background space-y-2">
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <p className="text-sm font-medium">{mapping.sourceTemplate}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">Section: {mapping.sourceSection}</p>
                      </div>
                      <Button variant="ghost" size="icon" className="h-6 w-6 -mt-1">
                        <MoreVertical className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                    <p className="text-xs">{mapping.instruction}</p>
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] text-muted-foreground">Order:</span>
                      <span className="text-xs font-mono">{mapping.order}</span>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-8">
                  <p className="text-sm text-muted-foreground">No mappings defined yet</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Add a mapping to start configuring AI content generation
                  </p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

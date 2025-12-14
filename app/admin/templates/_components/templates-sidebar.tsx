"use client"

import { Plus, Search } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import type { TemplateUI } from "../types"

interface TemplatesSidebarProps {
  templates: TemplateUI[]
  selectedTemplateId: string
  onSelect: (template: TemplateUI) => void
  onAddNew: () => void
  searchQuery: string
  onSearchChange: (query: string) => void
}

export function TemplatesSidebar({
  templates,
  selectedTemplateId,
  onSelect,
  onAddNew,
  searchQuery,
  onSearchChange,
}: TemplatesSidebarProps) {
  const filteredTemplates = templates.filter((t) => t.name.toLowerCase().includes(searchQuery.toLowerCase()))

  return (
    <div className="h-full flex flex-col bg-card border-r">
      <div className="p-4 border-b space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">Templates</h2>
          <Button size="sm" className="h-7 text-xs" onClick={onAddNew}>
            <Plus className="h-3.5 w-3.5 mr-1" />
            Add New
          </Button>
        </div>
        <div className="relative">
          <Search className="absolute left-2.5 top-2 h-3.5 w-3.5 text-muted-foreground" />
          <Input
            placeholder="Search templates..."
            className="pl-8 h-8 text-xs bg-background"
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </div>
      </div>
      <div className="flex-1 overflow-auto">
        {filteredTemplates.map((template) => (
          <div
            key={template.id}
            onClick={() => onSelect(template)}
            className={`px-4 py-3 border-b cursor-pointer transition-colors hover:bg-accent/50 ${
              selectedTemplateId === template.id ? "bg-accent border-l-2 border-l-primary" : ""
            }`}
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex-1 min-w-0">
                <h3 className="text-sm font-medium truncate">{template.name}</h3>
                <p className="text-xs text-muted-foreground mt-0.5">{template.version}</p>
              </div>
              <span
                className={`px-2 py-0.5 rounded-full text-[10px] font-medium shrink-0 ${
                  template.status === "Active"
                    ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                    : "bg-amber-500/10 text-amber-600 dark:text-amber-400"
                }`}
              >
                {template.status}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

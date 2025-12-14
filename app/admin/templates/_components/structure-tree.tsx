"use client"

import { useState } from "react"
import type React from "react"
import {
  ChevronRight,
  ChevronDown,
  MoreVertical,
  Trash2,
  MoveUp,
  MoveDown,
  Plus,
  GripVertical,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import type { TreeNode } from "../types"

interface StructureTreeProps {
  sections: TreeNode | null
  selectedSectionId: string | null
  onSelectSection: (section: TreeNode) => void
  onAddSection: () => void
  onDeleteSection?: () => void
  onReorderSection?: (action: "moveUp" | "moveDown" | "indent" | "outdent") => void
  onExpandAll?: () => void
  onCollapseAll?: () => void
  templateName?: string
}

interface TreeItemProps {
  node: TreeNode
  depth: number
  isSelected: boolean
  onSelect: () => void
  onDragStart: (node: TreeNode) => void
  onDragOver: (e: React.DragEvent, node: TreeNode) => void
  onDrop: (e: React.DragEvent, node: TreeNode) => void
  onDragEnd: () => void
  isDragging: boolean
  isDragOver: boolean
  onDeleteSection?: () => void
  onReorderSection?: (action: "moveUp" | "moveDown" | "indent" | "outdent") => void
}

function TreeItem({
  node,
  depth,
  isSelected,
  onSelect,
  onDragStart,
  onDragOver,
  onDrop,
  onDragEnd,
  isDragging,
  isDragOver,
  onDeleteSection,
  onReorderSection,
}: TreeItemProps) {
  const [isExpanded, setIsExpanded] = useState(true)
  const hasChildren = node.children.length > 0

  return (
    <div>
      <div
        draggable
        onDragStart={(e) => {
          e.stopPropagation()
          onDragStart(node)
        }}
        onDragOver={(e) => {
          e.preventDefault()
          e.stopPropagation()
          onDragOver(e, node)
        }}
        onDrop={(e) => {
          e.preventDefault()
          e.stopPropagation()
          onDrop(e, node)
        }}
        onDragEnd={onDragEnd}
        className={`flex items-center gap-2 px-3 py-1.5 cursor-pointer hover:bg-accent/50 transition-colors ${
          isSelected ? "bg-blue-500/10 border-l-2 border-l-blue-500" : ""
        } ${isDragging ? "opacity-40" : ""} ${isDragOver ? "border-t-2 border-t-blue-500" : ""}`}
        style={{ paddingLeft: `${depth * 1.5 + 0.75}rem` }}
        onClick={onSelect}
      >
        <GripVertical className="h-3.5 w-3.5 text-muted-foreground/50 cursor-grab active:cursor-grabbing shrink-0" />
        {hasChildren ? (
          <button
            onClick={(e) => {
              e.stopPropagation()
              setIsExpanded(!isExpanded)
            }}
            className="shrink-0"
          >
            {isExpanded ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            )}
          </button>
        ) : (
          <div className="w-4" />
        )}
        <span className="text-xs text-muted-foreground font-mono min-w-[2rem]">{node.number}</span>
        <span className="text-sm flex-1">{node.title}</span>
        <DropdownMenu>
          <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
            <Button variant="ghost" size="icon" className="h-6 w-6">
              <MoreVertical className="h-3.5 w-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem>
              <Plus className="mr-2 h-4 w-4" />
              Add Child
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={(e) => {
                e.stopPropagation()
                onReorderSection?.("moveUp")
              }}
            >
              <MoveUp className="mr-2 h-4 w-4" />
              Move Up
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={(e) => {
                e.stopPropagation()
                onReorderSection?.("moveDown")
              }}
            >
              <MoveDown className="mr-2 h-4 w-4" />
              Move Down
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={(e) => {
                e.stopPropagation()
                onReorderSection?.("indent")
              }}
            >
              Indent
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={(e) => {
                e.stopPropagation()
                onReorderSection?.("outdent")
              }}
            >
              Outdent
            </DropdownMenuItem>
            <DropdownMenuItem
              className="text-destructive"
              onClick={(e) => {
                e.stopPropagation()
                onDeleteSection?.()
              }}
            >
              <Trash2 className="mr-2 h-4 w-4" />
              Delete
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {isExpanded &&
        hasChildren &&
        node.children.map((child) => (
          <TreeItem
            key={child.id}
            node={child}
            depth={depth + 1}
            isSelected={isSelected}
            onSelect={onSelect}
            onDragStart={onDragStart}
            onDragOver={onDragOver}
            onDrop={onDrop}
            onDragEnd={onDragEnd}
            isDragging={isDragging}
            isDragOver={isDragOver}
            onDeleteSection={onDeleteSection}
            onReorderSection={onReorderSection}
          />
        ))}
    </div>
  )
}

export function StructureTree({
  sections,
  selectedSectionId,
  onSelectSection,
  onAddSection,
  onDeleteSection,
  onReorderSection,
  onExpandAll,
  onCollapseAll,
  templateName,
}: StructureTreeProps) {
  const [draggedNode, setDraggedNode] = useState<TreeNode | null>(null)
  const [dragOverNode, setDragOverNode] = useState<TreeNode | null>(null)

  const handleDragStart = (node: TreeNode) => {
    setDraggedNode(node)
  }

  const handleDragOver = (e: React.DragEvent, node: TreeNode) => {
    setDragOverNode(node)
  }

  const handleDrop = (e: React.DragEvent, node: TreeNode) => {
    console.log("[v0] Drop:", draggedNode?.title, "->", node.title)
    // Handle drop logic here
  }

  const handleDragEnd = () => {
    setDraggedNode(null)
    setDragOverNode(null)
  }

  if (!sections) {
    return (
      <div className="h-full flex flex-col bg-background">
        <div className="px-4 py-3 border-b flex items-center justify-between">
          <h2 className="text-sm font-semibold">{templateName || "Structure"}</h2>
          <div className="flex gap-2">
            <Button size="sm" className="h-7 text-xs" onClick={onAddSection}>
              <Plus className="h-3.5 w-3.5 mr-1" />
              Add Section
            </Button>
          </div>
        </div>
        <div className="flex-1 overflow-auto flex items-center justify-center">
          <div className="text-center text-sm text-muted-foreground">
            <p>Нет секций в шаблоне</p>
            <p className="text-xs mt-1">Добавьте первую секцию</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col bg-background">
      <div className="px-4 py-3 border-b flex items-center justify-between">
        <h2 className="text-sm font-semibold">{templateName || "Structure"}</h2>
        <div className="flex gap-2">
          <Button size="sm" className="h-7 text-xs" onClick={onAddSection}>
            <Plus className="h-3.5 w-3.5 mr-1" />
            Add Section
          </Button>
          {onExpandAll && (
            <Button variant="outline" size="sm" className="h-7 text-xs bg-transparent" onClick={onExpandAll}>
              Expand All
            </Button>
          )}
          {onCollapseAll && (
            <Button variant="outline" size="sm" className="h-7 text-xs bg-transparent" onClick={onCollapseAll}>
              Collapse All
            </Button>
          )}
        </div>
      </div>
      <div className="flex-1 overflow-auto">
        <TreeItem
          node={sections}
          depth={0}
          isSelected={selectedSectionId === sections.id}
          onSelect={() => onSelectSection(sections)}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          onDragEnd={handleDragEnd}
          isDragging={draggedNode?.id === sections.id}
          isDragOver={dragOverNode?.id === sections.id}
          onDeleteSection={onDeleteSection}
          onReorderSection={onReorderSection}
        />
      </div>
    </div>
  )
}

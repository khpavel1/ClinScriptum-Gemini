"use client"

import { useState, useTransition } from "react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FileText, Plus, Loader2 } from "lucide-react"
import { createDeliverableAction } from "@/app/projects/[id]/actions"

interface DocTemplate {
  id: string
  name: string
  description: string | null
  created_at: string
}

interface CreateDeliverableModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  projectId: string
  docTemplates: DocTemplate[]
}

export function CreateDeliverableModal({ 
  open, 
  onOpenChange, 
  projectId,
  docTemplates,
}: CreateDeliverableModalProps) {
  const [templateId, setTemplateId] = useState<string>("")
  const [title, setTitle] = useState<string>("")
  const [isPending, startTransition] = useTransition()

  const selectedTemplate = docTemplates.find((t) => t.id === templateId)

  const handleSubmit = () => {
    if (!templateId || !title) {
      alert("Заполните все обязательные поля")
      return
    }

    const formData = new FormData()
    formData.append("projectId", projectId)
    formData.append("templateId", templateId)
    formData.append("title", title)

    startTransition(async () => {
      const result = await createDeliverableAction(formData)
      
      if (result.error) {
        alert(`Ошибка: ${result.error}`)
      } else {
        alert("Документ успешно создан")
        // Reset form
        setTemplateId("")
        setTitle("")
        onOpenChange(false)
      }
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Создать новый документ</DialogTitle>
          <DialogDescription>
            Создайте новый документ на основе шаблона, используя исходные материалы
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Target Template Field */}
          <div className="space-y-2">
            <Label htmlFor="template" className="text-sm font-medium">
              Шаблон <span className="text-destructive">*</span>
            </Label>
            <Select value={templateId} onValueChange={setTemplateId}>
              <SelectTrigger id="template">
                <SelectValue placeholder="Выберите шаблон" />
              </SelectTrigger>
              <SelectContent>
                {docTemplates.map((template) => (
                  <SelectItem key={template.id} value={template.id}>
                    {template.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              Структура документа и секции будут основаны на этом шаблоне
            </p>
          </div>

          {/* Title Field */}
          <div className="space-y-2">
            <Label htmlFor="title" className="text-sm font-medium">
              Название документа <span className="text-destructive">*</span>
            </Label>
            <Input
              id="title"
              placeholder="например, Clinical Study Report v1.0"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Описательное название для идентификации этого документа
            </p>
          </div>

          {/* Template Preview */}
          {selectedTemplate && selectedTemplate.description && (
            <div className="rounded-lg border border-border bg-muted/30 p-4">
              <div className="mb-2 flex items-center gap-2">
                <FileText className="size-4 text-muted-foreground" />
                <span className="text-sm font-medium text-foreground">Описание шаблона:</span>
              </div>
              <p className="text-sm text-muted-foreground">{selectedTemplate.description}</p>
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={isPending}>
            Отмена
          </Button>
          <Button disabled={!templateId || !title || isPending} className="gap-2" onClick={handleSubmit}>
            {isPending ? (
              <>
                <Loader2 className="size-4 animate-spin" />
                Создание...
              </>
            ) : (
              <>
                <Plus className="size-4" />
                Создать документ
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

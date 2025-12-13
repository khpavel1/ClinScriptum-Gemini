"use client"

import type React from "react"

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
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Upload, FileText, Loader2 } from "lucide-react"
import { uploadSourceAction } from "@/app/projects/[id]/actions"

interface DocTemplate {
  id: string
  name: string
  description: string | null
  created_at: string
}

interface UploadSourceModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  projectId: string
  docTemplates: DocTemplate[]
}

export function UploadSourceModal({ 
  open, 
  onOpenChange, 
  projectId,
  docTemplates,
}: UploadSourceModalProps) {
  const [documentType, setDocumentType] = useState<string>("")
  const [templateId, setTemplateId] = useState<string>("")
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [dragActive, setDragActive] = useState(false)
  const [isPending, startTransition] = useTransition()

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true)
    } else if (e.type === "dragleave") {
      setDragActive(false)
    }
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setDragActive(false)
    
    const files = e.dataTransfer.files
    if (files && files.length > 0) {
      const file = files[0]
      if (file.type === "application/pdf") {
        setSelectedFile(file)
      } else {
        alert("Поддерживаются только PDF файлы")
      }
    }
  }

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files
    if (files && files.length > 0) {
      const file = files[0]
      if (file.type === "application/pdf") {
        setSelectedFile(file)
      } else {
        alert("Поддерживаются только PDF файлы")
      }
    }
  }

  const handleSubmit = () => {
    if (!documentType || !selectedFile) {
      alert("Заполните все обязательные поля")
      return
    }

    const formData = new FormData()
    formData.append("projectId", projectId)
    formData.append("file", selectedFile)
    formData.append("docType", documentType)
    if (templateId) {
      formData.append("templateId", templateId)
    }

    startTransition(async () => {
      const result = await uploadSourceAction(formData)
      
      if (result.error) {
        alert(`Ошибка: ${result.error}`)
      } else {
        alert("Документ загружен и отправлен на обработку")
        // Reset form
        setDocumentType("")
        setTemplateId("")
        setSelectedFile(null)
        onOpenChange(false)
      }
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Загрузить исходный документ</DialogTitle>
          <DialogDescription>
            Добавьте новый исходный документ для использования в генерации
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Document Type Field */}
          <div className="space-y-2">
            <Label htmlFor="document-type" className="text-sm font-medium">
              Тип документа <span className="text-destructive">*</span>
            </Label>
            <Select value={documentType} onValueChange={setDocumentType}>
              <SelectTrigger id="document-type">
                <SelectValue placeholder="Выберите тип документа" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="Protocol">Protocol</SelectItem>
                <SelectItem value="SAP">Statistical Analysis Plan (SAP)</SelectItem>
                <SelectItem value="CSR_Prev">CSR (Previous)</SelectItem>
                <SelectItem value="IB">Investigator Brochure</SelectItem>
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              Это помогает правильно категоризировать и индексировать документ
            </p>
          </div>

          {/* Template Field (Optional) */}
          {docTemplates.length > 0 && (
            <div className="space-y-2">
              <Label htmlFor="template" className="text-sm font-medium">
                Шаблон для классификации (опционально)
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
                Шаблон поможет правильно классифицировать секции документа
              </p>
            </div>
          )}

          {/* File Dropzone */}
          <div className="space-y-2">
            <Label className="text-sm font-medium">Файл</Label>
            <div
              className={`relative flex cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed px-6 py-10 transition-colors ${
                dragActive ? "border-primary bg-primary/5" : "border-border bg-muted/20 hover:bg-muted/30"
              }`}
              onDragEnter={handleDrag}
              onDragLeave={handleDrag}
              onDragOver={handleDrag}
              onDrop={handleDrop}
              onClick={() => document.getElementById("file-upload")?.click()}
            >
              <input
                id="file-upload"
                type="file"
                className="hidden"
                accept=".pdf"
                onChange={handleFileSelect}
              />
              <div className="mb-3 flex size-12 items-center justify-center rounded-full bg-primary/10">
                <Upload className="size-6 text-primary" />
              </div>
              {selectedFile ? (
                <>
                  <p className="mb-1 text-sm font-medium text-foreground">{selectedFile.name}</p>
                  <p className="text-xs text-muted-foreground">
                    {(selectedFile.size / 1024 / 1024).toFixed(2)} MB
                  </p>
                </>
              ) : (
                <>
                  <p className="mb-1 text-sm font-medium text-foreground">
                    Перетащите PDF файл сюда или нажмите для выбора
                  </p>
                  <p className="text-xs text-muted-foreground">Максимальный размер: 50MB</p>
                </>
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={isPending}>
            Отмена
          </Button>
          <Button 
            disabled={!documentType || !selectedFile || isPending} 
            className="gap-2"
            onClick={handleSubmit}
          >
            {isPending ? (
              <>
                <Loader2 className="size-4 animate-spin" />
                Загрузка...
              </>
            ) : (
              <>
                <FileText className="size-4" />
                Загрузить документ
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

"use client"

import { useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { UploadSourceModal } from "@/components/upload-source-modal"
import { FileText, Upload, CheckCircle2, Clock, XCircle } from "lucide-react"
import { Badge } from "@/components/ui/badge"

interface SourceDocument {
  id: string
  name: string
  doc_type: string | null
  status: string | null
  created_at: string | null
  storage_path: string
}

interface DocTemplate {
  id: string
  name: string
  description: string | null
  created_at: string
}

interface ProjectSourceDocumentsTabProps {
  sourceDocuments: SourceDocument[]
  docTemplates: DocTemplate[]
  projectId: string
}

export function ProjectSourceDocumentsTab({
  sourceDocuments,
  docTemplates,
  projectId,
}: ProjectSourceDocumentsTabProps) {
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)

  const getStatusBadge = (status: string | null) => {
    switch (status) {
      case "indexed":
        return (
          <Badge variant="default" className="gap-1">
            <CheckCircle2 className="h-3 w-3" />
            Обработан
          </Badge>
        )
      case "uploading":
        return (
          <Badge variant="secondary" className="gap-1">
            <Clock className="h-3 w-3" />
            Загрузка
          </Badge>
        )
      case "error":
        return (
          <Badge variant="destructive" className="gap-1">
            <XCircle className="h-3 w-3" />
            Ошибка
          </Badge>
        )
      default:
        return (
          <Badge variant="outline" className="gap-1">
            <Clock className="h-3 w-3" />
            {status || "Неизвестно"}
          </Badge>
        )
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Исходные документы</h2>
          <p className="text-muted-foreground">
            Загрузите исходные документы для использования в генерации
          </p>
        </div>
        <Button onClick={() => setIsUploadModalOpen(true)} className="gap-2">
          <Upload className="h-4 w-4" />
          Загрузить документ
        </Button>
      </div>

      {sourceDocuments.length === 0 ? (
        <Card>
          <CardContent className="pt-6">
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-muted">
                <FileText className="h-8 w-8 text-muted-foreground" />
              </div>
              <h3 className="mb-2 text-lg font-semibold">Нет загруженных документов</h3>
              <p className="mb-4 text-sm text-muted-foreground">
                Начните с загрузки исходного документа (Protocol, SAP, CSR и т.д.)
              </p>
              <Button onClick={() => setIsUploadModalOpen(true)} className="gap-2">
                <Upload className="h-4 w-4" />
                Загрузить первый документ
              </Button>
            </div>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {sourceDocuments.map((doc) => (
            <Card key={doc.id} className="hover:border-primary/50 transition-colors">
              <CardHeader>
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-3 flex-1">
                    <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                      <FileText className="h-5 w-5 text-primary" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <CardTitle className="text-base truncate">{doc.name}</CardTitle>
                      <CardDescription className="text-sm">
                        {doc.doc_type || "Не указан"}
                      </CardDescription>
                    </div>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Статус</span>
                  {getStatusBadge(doc.status)}
                </div>
                {doc.created_at && (
                  <div className="text-xs text-muted-foreground">
                    Загружен: {new Date(doc.created_at).toLocaleDateString("ru-RU")}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <UploadSourceModal
        open={isUploadModalOpen}
        onOpenChange={setIsUploadModalOpen}
        projectId={projectId}
        docTemplates={docTemplates}
      />
    </div>
  )
}

"use client"

import { useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import { Button } from "@/components/ui/button"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { FileText, Edit, Plus } from "lucide-react"
import { CreateDeliverableModal } from "@/components/create-deliverable-modal"

export interface Document {
  id: string | number
  title: string
  version: string
  progress: number
  icon: typeof FileText
  editors: Array<{ name: string; avatar: string }>
}

interface DocTemplate {
  id: string
  name: string
  description: string | null
  created_at: string
}

interface ProjectDocumentsTabProps {
  documents: Document[]
  docTemplates: DocTemplate[]
  projectId: string
}

export function ProjectDocumentsTab({ 
  documents, 
  docTemplates,
  projectId,
}: ProjectDocumentsTabProps) {
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)

  if (documents.length === 0) {
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-bold tracking-tight">Создаваемые документы</h2>
            <p className="text-muted-foreground">
              Создавайте документы на основе шаблонов
            </p>
          </div>
          <Button onClick={() => setIsCreateModalOpen(true)} className="gap-2">
            <Plus className="h-4 w-4" />
            Создать документ
          </Button>
        </div>
        <Card>
          <CardContent className="pt-6">
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-muted">
                <FileText className="h-8 w-8 text-muted-foreground" />
              </div>
              <h3 className="mb-2 text-lg font-semibold">Нет созданных документов</h3>
              <p className="mb-4 text-sm text-muted-foreground">
                Начните с создания документа на основе шаблона
              </p>
              <Button onClick={() => setIsCreateModalOpen(true)} className="gap-2">
                <Plus className="h-4 w-4" />
                Создать первый документ
              </Button>
            </div>
          </CardContent>
        </Card>
        <CreateDeliverableModal
          open={isCreateModalOpen}
          onOpenChange={setIsCreateModalOpen}
          projectId={projectId}
          docTemplates={docTemplates}
        />
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Создаваемые документы</h2>
          <p className="text-muted-foreground">
            Документы, созданные на основе шаблонов
          </p>
        </div>
        <Button onClick={() => setIsCreateModalOpen(true)} className="gap-2">
          <Plus className="h-4 w-4" />
          Создать документ
        </Button>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {documents.map((doc) => (
          <Card key={doc.id} className="hover:border-primary/50 transition-colors">
            <CardHeader>
              <div className="flex items-start justify-between">
                <div className="flex items-start gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                    <doc.icon className="h-5 w-5 text-primary" />
                  </div>
                  <div>
                    <CardTitle className="text-base">{doc.title}</CardTitle>
                    <CardDescription className="text-sm">{doc.version}</CardDescription>
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              {/* Progress */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Progress</span>
                  <span className="font-semibold">{doc.progress}%</span>
                </div>
                <Progress value={doc.progress} className="h-2" />
              </div>

              {/* Editors */}
              <div className="flex items-center justify-between">
                <div className="flex -space-x-2">
                  {doc.editors.map((editor, index) => (
                    <Avatar key={index} className="h-8 w-8 border-2 border-background">
                      <AvatarImage src={editor.avatar || "/placeholder.svg"} alt={editor.name} />
                      <AvatarFallback>
                        {editor.name
                          .split(" ")
                          .map((n) => n[0])
                          .join("")}
                      </AvatarFallback>
                    </Avatar>
                  ))}
                </div>
                <Button size="sm" className="gap-2">
                  <Edit className="h-4 w-4" />
                  Открыть редактор
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
      <CreateDeliverableModal
        open={isCreateModalOpen}
        onOpenChange={setIsCreateModalOpen}
        projectId={projectId}
        docTemplates={docTemplates}
      />
    </div>
  )
}

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import { Button } from "@/components/ui/button"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { FileText, Edit } from "lucide-react"

interface Document {
  id: number
  title: string
  version: string
  progress: number
  icon: typeof FileText
  editors: Array<{ name: string; avatar: string }>
}

interface ProjectDocumentsTabProps {
  documents: Document[]
}

export function ProjectDocumentsTab({ documents }: ProjectDocumentsTabProps) {
  if (documents.length === 0) {
    return (
      <Card>
        <CardContent className="pt-6">
          <p className="text-center text-muted-foreground">
            Документы пока не добавлены в этот проект.
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
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
  )
}

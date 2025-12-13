import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { FileStack, Users, Calendar } from "lucide-react"

interface ProjectHeaderProps {
  project: {
    study_code: string | null
    title: string
    sponsor: string | null
    therapeutic_area: string | null
    status: string
    created_at: string
  }
  documentsCount: number
  teamMembersCount: number
}

export function ProjectHeader({ project, documentsCount, teamMembersCount }: ProjectHeaderProps) {
  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-4xl font-bold tracking-tight text-balance">
            {project.study_code || project.title}
          </h1>
          <p className="text-muted-foreground mt-1 text-pretty">{project.title}</p>
          {project.sponsor && (
            <p className="text-sm text-muted-foreground mt-1">Спонсор: {project.sponsor}</p>
          )}
        </div>
        <div className="flex gap-2">
          {project.therapeutic_area && (
            <Badge variant="outline" className="bg-chart-1/10 text-chart-1 border-chart-1/20">
              {project.therapeutic_area}
            </Badge>
          )}
          <Badge 
            variant="outline" 
            className={
              project.status === 'active' 
                ? "bg-chart-2/10 text-chart-2 border-chart-2/20"
                : project.status === 'archived'
                ? "bg-muted text-muted-foreground border-border"
                : "bg-chart-4/10 text-chart-4 border-chart-4/20"
            }
          >
            {project.status}
          </Badge>
        </div>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
              <FileStack className="h-5 w-5 text-primary" />
            </div>
            <div>
              <p className="text-2xl font-bold">{documentsCount}</p>
              <p className="text-sm text-muted-foreground">Документы</p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-chart-2/10">
              <Users className="h-5 w-5 text-chart-2" />
            </div>
            <div>
              <p className="text-2xl font-bold">{teamMembersCount}</p>
              <p className="text-sm text-muted-foreground">Участники команды</p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-chart-4/10">
              <Calendar className="h-5 w-5 text-chart-4" />
            </div>
            <div>
              <p className="text-sm font-semibold">
                {project.created_at 
                  ? new Date(project.created_at).toLocaleDateString('ru-RU', {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                    })
                  : '—'
                }
              </p>
              <p className="text-sm text-muted-foreground">Дата создания</p>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

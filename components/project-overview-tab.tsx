import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

interface Project {
  title: string
  study_code: string | null
  sponsor: string | null
  therapeutic_area: string | null
  status: string
}

interface ProjectOverviewTabProps {
  project: Project
}

export function ProjectOverviewTab({ project }: ProjectOverviewTabProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Сводка проекта</CardTitle>
        <CardDescription>Ключевая информация об этом клиническом исследовании</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <div>
            <p className="text-sm font-medium mb-2">Название проекта:</p>
            <p className="text-sm text-muted-foreground leading-relaxed">{project.title}</p>
          </div>
          {project.study_code && (
            <div>
              <p className="text-sm font-medium mb-2">Код исследования:</p>
              <p className="text-sm text-muted-foreground leading-relaxed">{project.study_code}</p>
            </div>
          )}
          {project.sponsor && (
            <div>
              <p className="text-sm font-medium mb-2">Спонсор:</p>
              <p className="text-sm text-muted-foreground leading-relaxed">{project.sponsor}</p>
            </div>
          )}
          {project.therapeutic_area && (
            <div>
              <p className="text-sm font-medium mb-2">Терапевтическая область:</p>
              <p className="text-sm text-muted-foreground leading-relaxed">{project.therapeutic_area}</p>
            </div>
          )}
          <div>
            <p className="text-sm font-medium mb-2">Статус:</p>
            <p className="text-sm text-muted-foreground leading-relaxed">{project.status}</p>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

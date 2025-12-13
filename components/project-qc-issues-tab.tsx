import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"

interface QCTask {
  id: number
  title: string
  priority: "high" | "medium" | "low"
  assignee: string
}

interface ProjectQCIssuesTabProps {
  qcTasks: QCTask[]
}

export function ProjectQCIssuesTab({ qcTasks }: ProjectQCIssuesTabProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Проблемы контроля качества</CardTitle>
        <CardDescription>Отслеживание и решение проблем контроля качества</CardDescription>
      </CardHeader>
      <CardContent>
        {qcTasks.length === 0 ? (
          <p className="text-sm text-muted-foreground">Проблем контроля качества не найдено.</p>
        ) : (
          <div className="space-y-3">
            {qcTasks.map((task) => (
              <div key={task.id} className="space-y-2 pb-3 border-b last:border-0 last:pb-0">
                <div className="flex items-start gap-2">
                  <Badge
                    variant="outline"
                    className={
                      task.priority === "high"
                        ? "bg-destructive/10 text-destructive border-destructive/20"
                        : task.priority === "medium"
                          ? "bg-chart-4/10 text-chart-4 border-chart-4/20"
                          : "bg-muted text-muted-foreground border-border"
                    }
                  >
                    {task.priority}
                  </Badge>
                </div>
                <p className="text-sm leading-tight text-pretty">{task.title}</p>
                <p className="text-xs text-muted-foreground">Назначено: {task.assignee}</p>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

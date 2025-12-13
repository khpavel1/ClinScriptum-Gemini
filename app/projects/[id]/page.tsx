import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Breadcrumb,
  BreadcrumbList,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb"
import { CheckCircle2, AlertCircle, Clock, Edit, FileText } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { createClient } from "@/lib/supabase/server"
import { redirect, notFound } from "next/navigation"
import { ProjectHeader } from "@/components/project-header"
import { ProjectDocumentsTab } from "@/components/project-documents-tab"
import { ProjectSettingsTab } from "@/components/project-settings-tab"
import { ProjectOverviewTab } from "@/components/project-overview-tab"
import { ProjectSourceDocumentsTab } from "@/components/project-source-documents-tab"
import { ProjectQCIssuesTab } from "@/components/project-qc-issues-tab"

interface ProjectDetailsPageProps {
  params: Promise<{ id: string }> | { id: string }
}

export default async function ProjectDetailsPage({ params }: ProjectDetailsPageProps) {
  const supabase = await createClient()
  
  // Получаем текущего пользователя
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Если пользователя нет, редирект на /login
  if (!user) {
    redirect('/login')
  }

  // Обрабатываем params (может быть Promise в Next.js 15+)
  const resolvedParams = params instanceof Promise ? await params : params
  const projectId = resolvedParams.id

  // Получаем проект с проверкой доступа (только если пользователь является участником)
  const { data: project, error } = await supabase
    .from('projects')
    .select('*, project_members!inner(user_id)')
    .eq('id', projectId)
    .eq('project_members.user_id', user.id)
    .single()

  // Если проект не найден или нет доступа
  if (error || !project) {
    notFound()
  }

  // Получаем документы проекта (если есть таблица documents)
  // Пока используем пустой массив, так как структура документов может отличаться
  const documents: Array<{
    id: number
    title: string
    version: string
    progress: number
    icon: typeof FileText
    editors: Array<{ name: string; avatar: string }>
  }> = []

  // Получаем участников проекта для отображения
  const { data: projectMembers } = await supabase
    .from('project_members')
    .select('*, profiles(full_name, avatar_url, email)')
    .eq('project_id', projectId)

  const teamMembersCount = projectMembers?.length || 0

  // Моковые данные для активности и QC задач (пока нет соответствующих таблиц)
  const recentActivity: Array<{
    id: number
    user: string
    action: string
    time: string
    type: "edit" | "complete" | "comment" | "start"
  }> = []

  const qcTasks: Array<{
    id: number
    title: string
    priority: "high" | "medium" | "low"
    assignee: string
  }> = []

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto p-6 lg:p-8">
        <Breadcrumb className="mb-6">
          <BreadcrumbList>
            <BreadcrumbItem>
              <BreadcrumbLink href="/projects">Projects</BreadcrumbLink>
            </BreadcrumbItem>
            <BreadcrumbSeparator />
            <BreadcrumbItem>
              <BreadcrumbPage>{project.study_code || project.title}</BreadcrumbPage>
            </BreadcrumbItem>
          </BreadcrumbList>
        </Breadcrumb>

        <div className="flex flex-col lg:flex-row gap-6">
          {/* Main Content */}
          <div className="flex-1 space-y-6">
            {/* Project Header */}
            <ProjectHeader 
              project={project}
              documentsCount={documents.length}
              teamMembersCount={teamMembersCount}
            />

            {/* Tabs Navigation */}
            <Tabs defaultValue="documents" className="w-full">
              <TabsList className="w-full justify-start border-b rounded-none h-auto p-0 bg-transparent">
                <TabsTrigger
                  value="overview"
                  className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent"
                >
                  Обзор
                </TabsTrigger>
                <TabsTrigger
                  value="documents"
                  className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent"
                >
                  Документы (CSR)
                </TabsTrigger>
                <TabsTrigger
                  value="source-data"
                  className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent"
                >
                  Исходные данные (RAG)
                </TabsTrigger>
                <TabsTrigger
                  value="qc-issues"
                  className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent"
                >
                  Проблемы QC
                </TabsTrigger>
                <TabsTrigger
                  value="settings"
                  className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent"
                >
                  Настройки
                </TabsTrigger>
              </TabsList>

              {/* Overview Tab */}
              <TabsContent value="overview" className="mt-6 space-y-4">
                <ProjectOverviewTab project={project} />
              </TabsContent>

              {/* Documents Tab */}
              <TabsContent value="documents" className="mt-6">
                <ProjectDocumentsTab documents={documents} />
              </TabsContent>

              {/* Source Data Tab */}
              <TabsContent value="source-data" className="mt-6">
                <ProjectSourceDocumentsTab />
              </TabsContent>

              {/* QC Issues Tab */}
              <TabsContent value="qc-issues" className="mt-6">
                <ProjectQCIssuesTab qcTasks={qcTasks} />
              </TabsContent>

              {/* Settings Tab */}
              <TabsContent value="settings" className="mt-6">
                <ProjectSettingsTab />
              </TabsContent>
            </Tabs>
          </div>

          {/* Right Sidebar */}
          <div className="w-full lg:w-80 space-y-6">
            {/* Recent Activity */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Последняя активность</CardTitle>
              </CardHeader>
              <CardContent>
                {recentActivity.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Активность пока отсутствует.</p>
                ) : (
                  <div className="space-y-4">
                    {recentActivity.map((activity) => (
                    <div key={activity.id} className="flex gap-3">
                      <div className="flex-shrink-0 mt-1">
                        {activity.type === "complete" && <CheckCircle2 className="h-4 w-4 text-chart-2" />}
                        {activity.type === "edit" && <Edit className="h-4 w-4 text-chart-1" />}
                        {activity.type === "comment" && <AlertCircle className="h-4 w-4 text-chart-4" />}
                        {activity.type === "start" && <Clock className="h-4 w-4 text-muted-foreground" />}
                      </div>
                      <div className="flex-1 space-y-1">
                        <p className="text-sm font-medium leading-tight">{activity.user}</p>
                        <p className="text-sm text-muted-foreground leading-tight">{activity.action}</p>
                        <p className="text-xs text-muted-foreground">{activity.time}</p>
                      </div>
                    </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Pending QC Tasks */}
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Ожидающие задачи QC</CardTitle>
              </CardHeader>
              <CardContent>
                {qcTasks.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Нет ожидающих задач QC.</p>
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
          </div>
        </div>
      </div>
    </div>
  )
}

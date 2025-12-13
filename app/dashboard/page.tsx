import { redirect } from 'next/navigation'
import { Suspense } from 'react'
import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { CreateProjectModal as CreateProjectDialog } from '@/components/create-project-dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import Link from 'next/link'
import { ProjectFilter } from '@/components/project-filter'

interface DashboardPageProps {
  searchParams: Promise<{ status?: string }> | { status?: string }
}

export default async function DashboardPage({ searchParams }: DashboardPageProps) {
  const supabase = await createClient()
  
  // Получаем текущего пользователя
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Если пользователя нет, редирект на /login
  if (!user) {
    redirect('/login')
  }

  // Обрабатываем searchParams (может быть Promise в Next.js 16)
  const params = searchParams instanceof Promise ? await searchParams : searchParams
  const status = params.status

  // Получаем проекты, где текущий пользователь является участником
  let query = supabase
    .from('projects')
    .select('*, project_members!inner(user_id)')
    .eq('project_members.user_id', user.id)

  // Применяем фильтр по статусу, если он указан и не равен 'all'
  if (status && status !== 'all') {
    query = query.eq('status', status)
  }

  const { data: projects } = await query.order('created_at', { ascending: false })

  return (
    <div className="container mx-auto px-4 py-8 max-w-6xl">
      {/* Заголовок */}
      <div className="mb-8">
        <h1 className="text-3xl font-semibold text-slate-900">
          Welcome, {user.email}
        </h1>
      </div>

      {/* Секция "My Projects" */}
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <h2 className="text-2xl font-semibold text-slate-900">My Projects</h2>
          <div className="flex items-center gap-3">
            <Suspense fallback={<div className="w-[180px] h-10" />}>
              <ProjectFilter />
            </Suspense>
            <CreateProjectDialog />
          </div>
        </div>

        {/* Список проектов или заглушка */}
        {!projects || projects.length === 0 ? (
          <Card>
            <CardContent className="pt-6">
              <p className="text-center text-slate-600">
                No projects found. Create one to get started.
              </p>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {projects.map((project) => {
              const status = project.status || 'draft'
              const statusVariant = status === 'active' ? 'active' : status === 'archived' ? 'archived' : 'draft'
              
              return (
                <Card key={project.id}>
                  <CardHeader>
                    <CardTitle className="text-lg">
                      {project.study_code && (
                        <span className="font-mono text-sm text-slate-500 mr-2">
                          {project.study_code}
                        </span>
                      )}
                      {project.title || 'Untitled Project'}
                    </CardTitle>
                    <div className="flex items-center gap-2 mt-2">
                      <Badge variant={statusVariant}>
                        {status}
                      </Badge>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-3">
                      {project.created_at && (
                        <div className="text-sm text-slate-600">
                          <span className="font-medium">Создан:</span>{' '}
                          {new Date(project.created_at).toLocaleDateString('ru-RU', {
                            year: 'numeric',
                            month: 'short',
                            day: 'numeric',
                          })}
                        </div>
                      )}
                      <Link href={`/projects/${project.id}`}>
                        <Button className="w-full" variant="outline">
                          Open
                        </Button>
                      </Link>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}


import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { ProjectView } from "@/components/project-view"
import { FileText } from "lucide-react"

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

  // Получаем проект, где текущий пользователь является участником
  const { data: project, error: projectError } = await supabase
    .from('projects')
    .select('*, project_members!inner(user_id)')
    .eq('id', projectId)
    .eq('project_members.user_id', user.id)
    .single()

  if (projectError || !project) {
    redirect('/dashboard')
  }

  // Получаем количество документов
  const { count: documentsCount } = await supabase
    .from('deliverables')
    .select('*', { count: 'exact', head: true })
    .eq('project_id', projectId)

  // Получаем количество участников команды
  const { count: teamMembersCount } = await supabase
    .from('project_members')
    .select('*', { count: 'exact', head: true })
    .eq('project_id', projectId)

  // Загружаем список создаваемых документов (deliverables) для Таба 2
  const { data: deliverables } = await supabase
    .from('deliverables')
    .select('*')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false })

  // Загружаем список источников (source_documents) для Таба 1
  const { data: sourceDocuments } = await supabase
    .from('source_documents')
    .select('*')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false })

  // Загружаем список шаблонов (doc_templates) для модальных окон
  const { data: docTemplates } = await supabase
    .from('doc_templates')
    .select('*')
    .order('name', { ascending: true })

  return (
    <div className="min-h-screen bg-background">
      <ProjectView
        project={{
          id: project.id,
          title: project.title || 'Untitled Project',
          study_code: project.study_code,
          sponsor: project.sponsor,
          therapeutic_area: project.therapeutic_area,
          status: project.status || 'draft',
          created_at: project.created_at,
        }}
        documents={deliverables?.map((doc) => ({
          id: doc.id,
          title: doc.title || 'Untitled Document',
          version: '1.0',
          progress: 0,
          icon: FileText,
          editors: [],
        })) || []}
        documentsCount={documentsCount || 0}
        teamMembersCount={teamMembersCount || 0}
        qcTasks={[]}
        sourceDocuments={sourceDocuments || []}
        docTemplates={docTemplates || []}
        projectId={projectId}
      />
    </div>
  )
}
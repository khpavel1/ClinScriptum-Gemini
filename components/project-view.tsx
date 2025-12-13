"use client"

import { useState } from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ProjectHeader } from "@/components/project-header"
import { ProjectOverviewTab } from "@/components/project-overview-tab"
import { ProjectDocumentsTab, type Document } from "@/components/project-documents-tab"
import { ProjectSourceDocumentsTab } from "@/components/project-source-documents-tab"
import { ProjectQCIssuesTab } from "@/components/project-qc-issues-tab"
import { ProjectSettingsTab } from "@/components/project-settings-tab"

interface Project {
  id: string
  title: string
  study_code: string | null
  sponsor: string | null
  therapeutic_area: string | null
  status: string
  created_at: string
}

interface QCTask {
  id: number
  title: string
  priority: "high" | "medium" | "low"
  assignee: string
}

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

interface ProjectViewProps {
  project: Project
  documents?: Document[]
  documentsCount?: number
  teamMembersCount?: number
  qcTasks?: QCTask[]
  sourceDocuments?: SourceDocument[]
  docTemplates?: DocTemplate[]
  projectId: string
}

export function ProjectView({
  project,
  documents = [],
  documentsCount = 0,
  teamMembersCount = 0,
  qcTasks = [],
  sourceDocuments = [],
  docTemplates = [],
  projectId,
}: ProjectViewProps) {
  const [activeTab, setActiveTab] = useState("overview")

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <ProjectHeader
        project={project}
        documentsCount={documentsCount}
        teamMembersCount={teamMembersCount}
      />

      <Tabs value={activeTab} onValueChange={setActiveTab} className="mt-8">
        <TabsList className="grid w-full grid-cols-5">
          <TabsTrigger value="overview">Обзор</TabsTrigger>
          <TabsTrigger value="documents">Документы</TabsTrigger>
          <TabsTrigger value="sources">Источники</TabsTrigger>
          <TabsTrigger value="qc">QC</TabsTrigger>
          <TabsTrigger value="settings">Настройки</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="mt-6">
          <ProjectOverviewTab project={project} />
        </TabsContent>

        <TabsContent value="documents" className="mt-6">
          <ProjectDocumentsTab 
            documents={documents} 
            docTemplates={docTemplates}
            projectId={projectId}
          />
        </TabsContent>

        <TabsContent value="sources" className="mt-6">
          <ProjectSourceDocumentsTab 
            sourceDocuments={sourceDocuments}
            docTemplates={docTemplates}
            projectId={projectId}
          />
        </TabsContent>

        <TabsContent value="qc" className="mt-6">
          <ProjectQCIssuesTab qcTasks={qcTasks} />
        </TabsContent>

        <TabsContent value="settings" className="mt-6">
          <ProjectSettingsTab />
        </TabsContent>
      </Tabs>
    </div>
  )
}

"use client"

import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Placeholder from '@tiptap/extension-placeholder'
import { useEffect, useRef } from 'react'
import { Database } from '@/types/database.types'
import { useSectionEditorStore } from '@/lib/stores/section-editor-store'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

type DeliverableSection = Database['public']['Tables']['deliverable_sections']['Row']

interface SectionEditorProps {
  section: DeliverableSection
  onContentChange?: (sectionId: string, content: string) => void
  onSave?: (sectionId: string, content: string) => Promise<void>
  projectId: string
  deliverableId: string
}

export function SectionEditor({
  section,
  onContentChange,
  onSave,
  projectId,
  deliverableId,
}: SectionEditorProps) {
  const { 
    getUnsavedContent, 
    setUnsavedContent, 
    clearUnsavedContent,
    setDirty,
    isSectionDirty 
  } = useSectionEditorStore()
  
  const saveTimeoutRef = useRef<NodeJS.Timeout | null>(null)
  const isInitialMountRef = useRef(true)
  
  // Get initial content from store or section
  const initialContent = getUnsavedContent(section.id) || section.content_html || ''
  
  const editor = useEditor({
    extensions: [
      StarterKit,
      Placeholder.configure({
        placeholder: 'Начните вводить текст...',
      }),
    ],
    content: initialContent,
    editorProps: {
      attributes: {
        class: 'focus:outline-none min-h-[200px] p-4',
      },
    },
    onUpdate: ({ editor }) => {
      const html = editor.getHTML()
      
      // Save to store immediately
      setUnsavedContent(section.id, html)
      setDirty(section.id, true)
      
      // Call onChange callback
      onContentChange?.(section.id, html)
      
      // Auto-save after 2 seconds of inactivity
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current)
      }
      
      saveTimeoutRef.current = setTimeout(async () => {
        if (onSave && isSectionDirty(section.id)) {
          try {
            await onSave(section.id, html)
            setDirty(section.id, false)
          } catch (error) {
            console.error('Failed to save section:', error)
          }
        }
      }, 2000)
    },
  })
  
  // Restore content from store on mount if available
  useEffect(() => {
    if (editor && isInitialMountRef.current) {
      const unsavedContent = getUnsavedContent(section.id)
      if (unsavedContent && unsavedContent !== section.content_html) {
        editor.commands.setContent(unsavedContent)
      }
      isInitialMountRef.current = false
    }
  }, [editor, section.id, section.content_html, getUnsavedContent])
  
  // Update editor content when section content changes externally
  useEffect(() => {
    if (editor && !isInitialMountRef.current) {
      const currentContent = editor.getHTML()
      const unsavedContent = getUnsavedContent(section.id)
      const newContent = unsavedContent || section.content_html || ''
      
      // Only update if content actually changed and we don't have unsaved changes
      if (newContent !== currentContent && !isSectionDirty(section.id)) {
        editor.commands.setContent(newContent)
      }
    }
  }, [editor, section.content_html, section.id, getUnsavedContent, isSectionDirty])
  
  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current)
      }
    }
  }, [])
  
  if (!editor) {
    return (
      <Card className="mb-4">
        <CardContent className="pt-6">
          <div className="animate-pulse">Загрузка редактора...</div>
        </CardContent>
      </Card>
    )
  }
  
  const statusColors: Record<string, string> = {
    empty: 'bg-gray-500',
    draft_ai: 'bg-blue-500',
    in_progress: 'bg-yellow-500',
    review: 'bg-orange-500',
    approved: 'bg-green-500',
  }
  
  const statusLabels: Record<string, string> = {
    empty: 'Пустая',
    draft_ai: 'Черновик AI',
    in_progress: 'В работе',
    review: 'На проверке',
    approved: 'Одобрена',
  }
  
  return (
    <Card className="mb-4" data-section-id={section.id}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg">
            {section.custom_section_id ? `Секция ${section.id.slice(0, 8)}` : 'Секция'}
          </CardTitle>
          <div className="flex items-center gap-2">
            {isSectionDirty(section.id) && (
              <Badge variant="outline" className="text-xs">
                Не сохранено
              </Badge>
            )}
            <Badge 
              className={`${statusColors[section.status] || 'bg-gray-500'} text-white`}
            >
              {statusLabels[section.status] || section.status}
            </Badge>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <EditorContent editor={editor} />
      </CardContent>
    </Card>
  )
}

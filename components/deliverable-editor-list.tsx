"use client"

import { Virtuoso } from 'react-virtuoso'
import { useMemo, useCallback } from 'react'
import { Database } from '@/types/database.types'
import { SectionEditor } from '@/components/section-editor'
import { createClient } from '@/lib/supabase/client'

type DeliverableSection = Database['public']['Tables']['deliverable_sections']['Row']

interface DeliverableEditorListProps {
  sections: DeliverableSection[]
  projectId: string
  deliverableId: string
  onSectionUpdate?: (sectionId: string) => void
  className?: string
}

export function DeliverableEditorList({
  sections,
  projectId,
  deliverableId,
  onSectionUpdate,
  className = '',
}: DeliverableEditorListProps) {
  const supabase = createClient()
  
  // Sort sections by order if available, otherwise by created_at
  const sortedSections = useMemo(() => {
    return [...sections].sort((a, b) => {
      // If sections have order_index or similar, sort by that
      // Otherwise, sort by created_at
      return new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    })
  }, [sections])
  
  // Handle content change (immediate update to store)
  const handleContentChange = useCallback((sectionId: string, content: string) => {
    // Content is already saved to store by SectionEditor
    // This callback can be used for additional logic if needed
    onSectionUpdate?.(sectionId)
  }, [onSectionUpdate])
  
  // Handle save (persist to database)
  const handleSave = useCallback(async (sectionId: string, content: string) => {
    try {
      const { error } = await supabase
        .from('deliverable_sections')
        .update({
          content_html: content,
          updated_at: new Date().toISOString(),
        })
        .eq('id', sectionId)
      
      if (error) {
        console.error('Error saving section:', error)
        throw error
      }
      
      onSectionUpdate?.(sectionId)
    } catch (error) {
      console.error('Failed to save section:', error)
      throw error
    }
  }, [supabase, onSectionUpdate])
  
  // Render individual section item
  // When using 'data' prop, itemContent receives (index, item) where item is from the data array
  const itemContent = useCallback((index: number, section: DeliverableSection) => {
    if (!section) return null
    
    return (
      <div style={{ padding: '0.5rem 0' }}>
        <SectionEditor
          section={section}
          projectId={projectId}
          deliverableId={deliverableId}
          onContentChange={handleContentChange}
          onSave={handleSave}
        />
      </div>
    )
  }, [projectId, deliverableId, handleContentChange, handleSave])
  
  if (sortedSections.length === 0) {
    return (
      <div className={`flex items-center justify-center py-12 ${className}`}>
        <div className="text-center">
          <p className="text-muted-foreground">Нет секций для отображения</p>
        </div>
      </div>
    )
  }
  
  return (
    <div className={className} style={{ height: '100%', minHeight: '600px' }}>
      <Virtuoso
        style={{ height: '100%' }}
        data={sortedSections}
        itemContent={itemContent}
        // Use defaultItemHeight as a hint for initial rendering
        // Virtuoso will automatically measure and adjust for dynamic heights
        defaultItemHeight={300}
        // Increase overscan for smoother scrolling with complex editors
        overscan={3}
        // Enable smooth scrolling with increased viewport
        increaseViewportBy={{ top: 200, bottom: 200 }}
      />
    </div>
  )
}

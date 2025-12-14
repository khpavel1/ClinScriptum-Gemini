import { create } from 'zustand'
import { Database } from '@/types/database.types'

type DeliverableSection = Database['public']['Tables']['deliverable_sections']['Row']

// Store для управления состоянием несохраненного контента секций
interface SectionEditorStore {
  // Хранилище несохраненного контента по ID секции
  unsavedContent: Record<string, string>
  
  // Хранилище состояния "грязности" (изменен ли контент)
  isDirty: Record<string, boolean>
  
  // Сохранить несохраненный контент для секции
  setUnsavedContent: (sectionId: string, content: string) => void
  
  // Получить несохраненный контент для секции
  getUnsavedContent: (sectionId: string) => string | null
  
  // Очистить несохраненный контент для секции
  clearUnsavedContent: (sectionId: string) => void
  
  // Отметить секцию как "грязную" (измененную)
  setDirty: (sectionId: string, dirty: boolean) => void
  
  // Проверить, изменена ли секция
  isSectionDirty: (sectionId: string) => boolean
  
  // Очистить все несохраненные данные
  clearAll: () => void
}

export const useSectionEditorStore = create<SectionEditorStore>((set, get) => ({
  unsavedContent: {},
  isDirty: {},
  
  setUnsavedContent: (sectionId: string, content: string) => {
    set((state) => ({
      unsavedContent: {
        ...state.unsavedContent,
        [sectionId]: content,
      },
      isDirty: {
        ...state.isDirty,
        [sectionId]: true,
      },
    }))
  },
  
  getUnsavedContent: (sectionId: string) => {
    return get().unsavedContent[sectionId] || null
  },
  
  clearUnsavedContent: (sectionId: string) => {
    set((state) => {
      const { [sectionId]: _, ...unsavedContent } = state.unsavedContent
      const { [sectionId]: __, ...isDirty } = state.isDirty
      return {
        unsavedContent,
        isDirty,
      }
    })
  },
  
  setDirty: (sectionId: string, dirty: boolean) => {
    set((state) => ({
      isDirty: {
        ...state.isDirty,
        [sectionId]: dirty,
      },
    }))
  },
  
  isSectionDirty: (sectionId: string) => {
    return get().isDirty[sectionId] || false
  },
  
  clearAll: () => {
    set({
      unsavedContent: {},
      isDirty: {},
    })
  },
}))

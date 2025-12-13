export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      canonical_anchors: {
        Row: {
          anchor_text: string
          canonical_code: string
          created_at: string | null
          embedding: string | null
          id: string
        }
        Insert: {
          anchor_text: string
          canonical_code: string
          created_at?: string | null
          embedding?: string | null
          id?: string
        }
        Update: {
          anchor_text?: string
          canonical_code?: string
          created_at?: string | null
          embedding?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "canonical_anchors_canonical_code_fkey"
            columns: ["canonical_code"]
            isOneToOne: false
            referencedRelation: "canonical_sections"
            referencedColumns: ["code"]
          },
        ]
      }
      canonical_sections: {
        Row: {
          code: string
          created_at: string | null
          description: string | null
          name: string
        }
        Insert: {
          code: string
          created_at?: string | null
          description?: string | null
          name: string
        }
        Update: {
          code?: string
          created_at?: string | null
          description?: string | null
          name?: string
        }
        Relationships: []
      }
      deliverable_sections: {
        Row: {
          content_html: string | null
          created_at: string
          deliverable_id: string
          id: string
          status: string
          template_section_id: string
          updated_at: string
          used_source_section_ids: string[] | null
        }
        Insert: {
          content_html?: string | null
          created_at?: string
          deliverable_id: string
          id?: string
          status?: string
          template_section_id: string
          updated_at?: string
          used_source_section_ids?: string[] | null
        }
        Update: {
          content_html?: string | null
          created_at?: string
          deliverable_id?: string
          id?: string
          status?: string
          template_section_id?: string
          updated_at?: string
          used_source_section_ids?: string[] | null
        }
        Relationships: [
          {
            foreignKeyName: "deliverable_sections_deliverable_id_fkey"
            columns: ["deliverable_id"]
            isOneToOne: false
            referencedRelation: "deliverables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliverable_sections_template_section_id_fkey"
            columns: ["template_section_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      deliverables: {
        Row: {
          created_at: string
          id: string
          project_id: string
          status: string
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          project_id: string
          status?: string
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          project_id?: string
          status?: string
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "deliverables_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliverables_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "doc_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      doc_templates: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      organization_members: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          name: string
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string
          full_name: string | null
          id: string
          organization_id: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          organization_id?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          organization_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      project_members: {
        Row: {
          created_at: string
          id: string
          project_id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          project_id: string
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          project_id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          created_by: string
          id: string
          organization_id: string
          sponsor: string | null
          status: string
          study_code: string
          therapeutic_area: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          organization_id: string
          sponsor?: string | null
          status?: string
          study_code: string
          therapeutic_area?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          organization_id?: string
          sponsor?: string | null
          status?: string
          study_code?: string
          therapeutic_area?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      section_mappings: {
        Row: {
          created_at: string
          id: string
          instruction: string | null
          relationship_type: string
          source_section_id: string
          target_section_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instruction?: string | null
          relationship_type: string
          source_section_id: string
          target_section_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instruction?: string | null
          relationship_type?: string
          source_section_id?: string
          target_section_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "section_mappings_source_section_id_fkey"
            columns: ["source_section_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "section_mappings_target_section_id_fkey"
            columns: ["target_section_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      source_documents: {
        Row: {
          created_at: string | null
          detected_tables_count: number | null
          doc_type: string | null
          id: string
          name: string
          parsing_metadata: Json | null
          parsing_quality_comment: string | null
          parsing_quality_score: number | null
          project_id: string | null
          status: string | null
          storage_path: string
        }
        Insert: {
          created_at?: string | null
          detected_tables_count?: number | null
          doc_type?: string | null
          id?: string
          name: string
          parsing_metadata?: Json | null
          parsing_quality_comment?: string | null
          parsing_quality_score?: number | null
          project_id?: string | null
          status?: string | null
          storage_path: string
        }
        Update: {
          created_at?: string | null
          detected_tables_count?: number | null
          doc_type?: string | null
          id?: string
          name?: string
          parsing_metadata?: Json | null
          parsing_quality_comment?: string | null
          parsing_quality_score?: number | null
          project_id?: string | null
          status?: string | null
          storage_path?: string
        }
        Relationships: [
          {
            foreignKeyName: "source_documents_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      source_sections: {
        Row: {
          canonical_code: string | null
          classification_confidence: number | null
          content_markdown: string | null
          content_text: string | null
          created_at: string | null
          document_id: string | null
          embedding: string | null
          header: string | null
          id: string
          page_number: number | null
          section_number: string | null
          template_section_id: string | null
        }
        Insert: {
          canonical_code?: string | null
          classification_confidence?: number | null
          content_markdown?: string | null
          content_text?: string | null
          created_at?: string | null
          document_id?: string | null
          embedding?: string | null
          header?: string | null
          id?: string
          page_number?: number | null
          section_number?: string | null
          template_section_id?: string | null
        }
        Update: {
          canonical_code?: string | null
          classification_confidence?: number | null
          content_markdown?: string | null
          content_text?: string | null
          created_at?: string | null
          document_id?: string | null
          embedding?: string | null
          header?: string | null
          id?: string
          page_number?: number | null
          section_number?: string | null
          template_section_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "document_sections_canonical_code_fkey"
            columns: ["canonical_code"]
            isOneToOne: false
            referencedRelation: "canonical_sections"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "document_sections_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "source_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_sections_template_section_id_fkey"
            columns: ["template_section_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_sections_canonical_code_fkey"
            columns: ["canonical_code"]
            isOneToOne: false
            referencedRelation: "canonical_sections"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "source_sections_template_section_id_fkey"
            columns: ["template_section_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      study_globals: {
        Row: {
          created_at: string | null
          id: string
          project_id: string | null
          source_section_id: string | null
          variable_name: string | null
          variable_value: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          project_id?: string | null
          source_section_id?: string | null
          variable_name?: string | null
          variable_value?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          project_id?: string | null
          source_section_id?: string | null
          variable_name?: string | null
          variable_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "study_globals_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "study_globals_source_section_id_fkey"
            columns: ["source_section_id"]
            isOneToOne: false
            referencedRelation: "source_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      template_sections: {
        Row: {
          created_at: string
          description: string | null
          embedding: string | null
          id: string
          is_mandatory: boolean
          parent_id: string | null
          section_number: string | null
          template_id: string
          title: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          id?: string
          is_mandatory?: boolean
          parent_id?: string | null
          section_number?: string | null
          template_id: string
          title: string
        }
        Update: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          id?: string
          is_mandatory?: boolean
          parent_id?: string | null
          section_number?: string | null
          template_id?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_sections_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "template_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_sections_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "doc_templates"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      create_source_document: {
        Args: {
          p_doc_type: string
          p_name: string
          p_project_id: string
          p_storage_path: string
          p_user_id: string
        }
        Returns: string
      }
      create_user_organization: {
        Args: { creator_user_id: string; org_name: string; org_slug: string }
        Returns: string
      }
      create_user_project: {
        Args: {
          p_created_by: string
          p_organization_id: string
          p_sponsor: string
          p_status: string
          p_study_code: string
          p_title: string
        }
        Returns: string
      }
      has_project_access: {
        Args: { check_user_id: string; proj_id: string }
        Returns: boolean
      }
      is_org_admin: {
        Args: { check_user_id: string; org_id: string }
        Returns: boolean
      }
      is_org_member: {
        Args: { check_user_id: string; org_id: string }
        Returns: boolean
      }
      is_project_owner: {
        Args: { check_user_id: string; proj_id: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

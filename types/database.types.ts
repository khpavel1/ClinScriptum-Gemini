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
      custom_mappings: {
        Row: {
          created_at: string
          id: string
          instruction: string | null
          order_index: number
          source_custom_section_id: string | null
          source_ideal_section_id: string | null
          target_custom_section_id: string
          target_ideal_section_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          instruction?: string | null
          order_index?: number
          source_custom_section_id?: string | null
          source_ideal_section_id?: string | null
          target_custom_section_id: string
          target_ideal_section_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          instruction?: string | null
          order_index?: number
          source_custom_section_id?: string | null
          source_ideal_section_id?: string | null
          target_custom_section_id?: string
          target_ideal_section_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "custom_mappings_source_custom_section_id_fkey"
            columns: ["source_custom_section_id"]
            isOneToOne: false
            referencedRelation: "custom_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_mappings_source_ideal_section_id_fkey"
            columns: ["source_ideal_section_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_mappings_target_custom_section_id_fkey"
            columns: ["target_custom_section_id"]
            isOneToOne: false
            referencedRelation: "custom_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_mappings_target_ideal_section_id_fkey"
            columns: ["target_ideal_section_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_sections: {
        Row: {
          created_at: string
          custom_template_id: string
          id: string
          ideal_section_id: string | null
          order_index: number
          parent_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          custom_template_id: string
          id?: string
          ideal_section_id?: string | null
          order_index?: number
          parent_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          custom_template_id?: string
          id?: string
          ideal_section_id?: string | null
          order_index?: number
          parent_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_sections_custom_template_id_fkey"
            columns: ["custom_template_id"]
            isOneToOne: false
            referencedRelation: "custom_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_sections_ideal_section_id_fkey"
            columns: ["ideal_section_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_sections_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "custom_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_templates: {
        Row: {
          base_ideal_template_id: string
          created_at: string
          id: string
          name: string
          project_id: string | null
          updated_at: string
        }
        Insert: {
          base_ideal_template_id: string
          created_at?: string
          id?: string
          name: string
          project_id?: string | null
          updated_at?: string
        }
        Update: {
          base_ideal_template_id?: string
          created_at?: string
          id?: string
          name?: string
          project_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_templates_base_ideal_template_id_fkey"
            columns: ["base_ideal_template_id"]
            isOneToOne: false
            referencedRelation: "ideal_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_templates_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      deliverable_section_history: {
        Row: {
          change_reason: string | null
          changed_by_user_id: string
          content_snapshot: string
          created_at: string
          id: string
          section_id: string
        }
        Insert: {
          change_reason?: string | null
          changed_by_user_id: string
          content_snapshot: string
          created_at?: string
          id?: string
          section_id: string
        }
        Update: {
          change_reason?: string | null
          changed_by_user_id?: string
          content_snapshot?: string
          created_at?: string
          id?: string
          section_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "deliverable_section_history_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "deliverable_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      deliverable_sections: {
        Row: {
          content_html: string | null
          created_at: string
          custom_section_id: string | null
          deliverable_id: string
          id: string
          locked_at: string | null
          locked_by_user_id: string | null
          parent_id: string | null
          status: string
          updated_at: string
          used_source_section_ids: string[] | null
        }
        Insert: {
          content_html?: string | null
          created_at?: string
          custom_section_id?: string | null
          deliverable_id: string
          id?: string
          locked_at?: string | null
          locked_by_user_id?: string | null
          parent_id?: string | null
          status?: string
          updated_at?: string
          used_source_section_ids?: string[] | null
        }
        Update: {
          content_html?: string | null
          created_at?: string
          custom_section_id?: string | null
          deliverable_id?: string
          id?: string
          locked_at?: string | null
          locked_by_user_id?: string | null
          parent_id?: string | null
          status?: string
          updated_at?: string
          used_source_section_ids?: string[] | null
        }
        Relationships: [
          {
            foreignKeyName: "deliverable_sections_custom_section_id_fkey"
            columns: ["custom_section_id"]
            isOneToOne: false
            referencedRelation: "custom_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliverable_sections_deliverable_id_fkey"
            columns: ["deliverable_id"]
            isOneToOne: false
            referencedRelation: "deliverables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliverable_sections_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "deliverable_sections"
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
            referencedRelation: "custom_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      ideal_mappings: {
        Row: {
          created_at: string
          id: string
          instruction: string | null
          order_index: number
          source_ideal_section_id: string
          target_ideal_section_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instruction?: string | null
          order_index?: number
          source_ideal_section_id: string
          target_ideal_section_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instruction?: string | null
          order_index?: number
          source_ideal_section_id?: string
          target_ideal_section_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ideal_mappings_source_ideal_section_id_fkey"
            columns: ["source_ideal_section_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ideal_mappings_target_ideal_section_id_fkey"
            columns: ["target_ideal_section_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      ideal_sections: {
        Row: {
          created_at: string
          embedding: string | null
          id: string
          order_index: number
          parent_id: string | null
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          embedding?: string | null
          id?: string
          order_index?: number
          parent_id?: string | null
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          embedding?: string | null
          id?: string
          order_index?: number
          parent_id?: string | null
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ideal_sections_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "ideal_sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ideal_sections_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "ideal_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      ideal_templates: {
        Row: {
          created_at: string
          group_id: string | null
          id: string
          is_active: boolean
          name: string
          updated_at: string
          version: number
        }
        Insert: {
          created_at?: string
          group_id?: string | null
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
          version?: number
        }
        Update: {
          created_at?: string
          group_id?: string | null
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
          version?: number
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
      source_documents: {
        Row: {
          created_at: string | null
          detected_tables_count: number | null
          doc_type: string | null
          file_path: string | null
          id: string
          input_type: Database["public"]["Enums"]["input_type_enum"] | null
          is_current_version: boolean | null
          name: string
          parent_document_id: string | null
          parsing_metadata: Json | null
          parsing_quality_comment: string | null
          parsing_quality_score: number | null
          project_id: string | null
          status: string | null
          storage_path: string
          template_id: string | null
          version_label: string | null
        }
        Insert: {
          created_at?: string | null
          detected_tables_count?: number | null
          doc_type?: string | null
          file_path?: string | null
          id?: string
          input_type?: Database["public"]["Enums"]["input_type_enum"] | null
          is_current_version?: boolean | null
          name: string
          parent_document_id?: string | null
          parsing_metadata?: Json | null
          parsing_quality_comment?: string | null
          parsing_quality_score?: number | null
          project_id?: string | null
          status?: string | null
          storage_path: string
          template_id?: string | null
          version_label?: string | null
        }
        Update: {
          created_at?: string | null
          detected_tables_count?: number | null
          doc_type?: string | null
          file_path?: string | null
          id?: string
          input_type?: Database["public"]["Enums"]["input_type_enum"] | null
          is_current_version?: boolean | null
          name?: string
          parent_document_id?: string | null
          parsing_metadata?: Json | null
          parsing_quality_comment?: string | null
          parsing_quality_score?: number | null
          project_id?: string | null
          status?: string | null
          storage_path?: string
          template_id?: string | null
          version_label?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "source_documents_parent_document_id_fkey"
            columns: ["parent_document_id"]
            isOneToOne: false
            referencedRelation: "source_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_documents_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_documents_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "custom_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      source_sections: {
        Row: {
          bbox: Json | null
          classification_confidence: number | null
          content_markdown: string | null
          content_text: string | null
          created_at: string | null
          custom_section_id: string | null
          document_id: string | null
          embedding: string | null
          header: string | null
          id: string
          page_number: number | null
          section_number: string | null
          template_section_id: string | null
        }
        Insert: {
          bbox?: Json | null
          classification_confidence?: number | null
          content_markdown?: string | null
          content_text?: string | null
          created_at?: string | null
          custom_section_id?: string | null
          document_id?: string | null
          embedding?: string | null
          header?: string | null
          id?: string
          page_number?: number | null
          section_number?: string | null
          template_section_id?: string | null
        }
        Update: {
          bbox?: Json | null
          classification_confidence?: number | null
          content_markdown?: string | null
          content_text?: string | null
          created_at?: string | null
          custom_section_id?: string | null
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
            foreignKeyName: "document_sections_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "source_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_sections_custom_section_id_fkey"
            columns: ["custom_section_id"]
            isOneToOne: false
            referencedRelation: "custom_sections"
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
          p_therapeutic_area: string
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
      unlock_stale_deliverable_sections: {
        Args: { timeout_minutes?: number }
        Returns: number
      }
    }
    Enums: {
      deliverable_section_status_enum:
        | "empty"
        | "draft_ai"
        | "in_progress"
        | "review"
        | "approved"
      input_type_enum: "file" | "manual_entry"
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
    Enums: {
      deliverable_section_status_enum: [
        "empty",
        "draft_ai",
        "in_progress",
        "review",
        "approved",
      ],
      input_type_enum: ["file", "manual_entry"],
    },
  },
} as const

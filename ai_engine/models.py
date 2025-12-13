"""
SQLAlchemy модели для всех таблиц системы.
Соответствуют схеме Template Graph Architecture.
"""
from sqlalchemy import String, Integer, Text, ForeignKey, DateTime, Boolean, JSON
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import mapped_column, relationship
from sqlalchemy.sql import func, text
from pgvector.sqlalchemy import Vector
from database import Base
import uuid


class DocTemplate(Base):
    """
    Модель для таблицы doc_templates.
    Типы документов (шаблоны) - золотые стандарты структур.
    """
    __tablename__ = "doc_templates"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = mapped_column(String, unique=True, nullable=False)
    description = mapped_column(Text, nullable=True)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    sections = relationship("TemplateSection", back_populates="template", cascade="all, delete-orphan")
    deliverables = relationship("Deliverable", back_populates="template", cascade="all, delete-orphan")


class TemplateSection(Base):
    """
    Модель для таблицы template_sections.
    Узлы графа шаблонов - структура секций документа (Золотой стандарт).
    """
    __tablename__ = "template_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    template_id = mapped_column(UUID(as_uuid=True), ForeignKey("doc_templates.id", ondelete="CASCADE"), nullable=False)
    parent_id = mapped_column(UUID(as_uuid=True), ForeignKey("template_sections.id", ondelete="CASCADE"), nullable=True)
    section_number = mapped_column(String, nullable=True)  # например "3.1"
    title = mapped_column(Text, nullable=False)  # название секции
    description = mapped_column(Text, nullable=True)  # инструкция для AI
    is_mandatory = mapped_column(Boolean, nullable=False, default=True)
    embedding = mapped_column(Vector(1536), nullable=True)  # вектор для семантического поиска
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    template = relationship("DocTemplate", back_populates="sections")
    parent = relationship("TemplateSection", remote_side=[id], backref="children")
    source_mappings = relationship("SectionMapping", foreign_keys="SectionMapping.source_section_id", back_populates="source_section")
    target_mappings = relationship("SectionMapping", foreign_keys="SectionMapping.target_section_id", back_populates="target_section")
    source_sections = relationship("SourceSection", back_populates="template_section")
    deliverable_sections = relationship("DeliverableSection", back_populates="template_section")


class SectionMapping(Base):
    """
    Модель для таблицы section_mappings.
    Ребра графа шаблонов - правила переноса данных между секциями.
    """
    __tablename__ = "section_mappings"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    source_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("template_sections.id", ondelete="CASCADE"), nullable=False)
    target_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("template_sections.id", ondelete="CASCADE"), nullable=False)
    relationship_type = mapped_column(String, nullable=False)  # 'direct_copy', 'summary', 'transformation', 'consistency_check'
    instruction = mapped_column(Text, nullable=True)  # промпт для трансформации
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    source_section = relationship("TemplateSection", foreign_keys=[source_section_id], back_populates="source_mappings")
    target_section = relationship("TemplateSection", foreign_keys=[target_section_id], back_populates="target_mappings")


class SourceDocument(Base):
    """
    Модель для таблицы source_documents.
    Метаданные исходных документов.
    """
    __tablename__ = "source_documents"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    name = mapped_column(String, nullable=False)
    storage_path = mapped_column(String, nullable=False)
    doc_type = mapped_column(String, nullable=True)  # 'Protocol', 'SAP', 'Brochure'
    status = mapped_column(String, nullable=False, default="uploading")  # 'uploading', 'indexed', 'error'
    parsing_metadata = mapped_column(JSON, nullable=True, default={})  # Техн. метрики (время, кол-во страниц)
    parsing_quality_score = mapped_column(Integer, nullable=True)  # Оценка пользователя (1-5)
    parsing_quality_comment = mapped_column(Text, nullable=True)  # Комментарий к ошибке
    detected_tables_count = mapped_column(Integer, nullable=False, default=0)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    sections = relationship("SourceSection", back_populates="source_document", cascade="all, delete-orphan")


class SourceSection(Base):
    """
    Модель для таблицы source_sections.
    Хранит структурированные секции исходных документов (Inputs) с поддержкой векторов для гибридного поиска.
    """
    __tablename__ = "source_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_id = mapped_column(UUID(as_uuid=True), ForeignKey("source_documents.id", ondelete="CASCADE"), nullable=False)
    template_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("template_sections.id", ondelete="SET NULL"), nullable=True)
    
    # Структурные поля
    section_number = mapped_column(String, nullable=True)  # например "3.1.2"
    header = mapped_column(Text, nullable=True)  # например "Критерии включения"
    page_number = mapped_column(Integer, nullable=True)
    
    # Контент
    content_text = mapped_column(Text, nullable=True)  # Чистый текст для поиска
    content_markdown = mapped_column(Text, nullable=True)  # Текст с разметкой таблиц (для LLM)
    
    # Вектор для гибридного поиска
    embedding = mapped_column(Vector(1536), nullable=True)
    
    # Классификация (legacy поля из старой схемы)
    canonical_code = mapped_column(String, nullable=True)
    classification_confidence = mapped_column(Integer, nullable=True)  # FLOAT в БД, но используем Integer для совместимости
    
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    source_document = relationship("SourceDocument", back_populates="sections")
    template_section = relationship("TemplateSection", back_populates="source_sections")


class StudyGlobal(Base):
    """
    Модель для таблицы study_globals.
    Хранит глобальные переменные исследования (Паспорт исследования).
    """
    __tablename__ = "study_globals"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    variable_name = mapped_column(String, nullable=True)  # "Phase", "Drug_Name", "Primary_Endpoint" и т.д.
    variable_value = mapped_column(Text, nullable=True)  # Значение переменной
    source_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("source_sections.id", ondelete="SET NULL"), nullable=True)
    
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Deliverable(Base):
    """
    Модель для таблицы deliverables.
    Готовые документы (Outputs/Deliverables), созданные на основе шаблонов.
    """
    __tablename__ = "deliverables"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    template_id = mapped_column(UUID(as_uuid=True), ForeignKey("doc_templates.id", ondelete="RESTRICT"), nullable=False)
    title = mapped_column(Text, nullable=False)
    status = mapped_column(String, nullable=False, default="draft")  # 'draft', 'final'
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    template = relationship("DocTemplate", back_populates="deliverables")
    sections = relationship("DeliverableSection", back_populates="deliverable", cascade="all, delete-orphan")


class DeliverableSection(Base):
    """
    Модель для таблицы deliverable_sections.
    Секции готовых документов (Outputs) с контентом для редактора.
    """
    __tablename__ = "deliverable_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    deliverable_id = mapped_column(UUID(as_uuid=True), ForeignKey("deliverables.id", ondelete="CASCADE"), nullable=False)
    template_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("template_sections.id", ondelete="RESTRICT"), nullable=False)
    content_html = mapped_column(Text, nullable=True)  # HTML контент для редактора Tiptap
    status = mapped_column(String, nullable=False, default="empty")  # 'empty', 'generated', 'reviewed'
    used_source_section_ids = mapped_column(ARRAY(UUID(as_uuid=True)), nullable=False, server_default=text("ARRAY[]::UUID[]"))  # Массив ссылок на source_sections
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    deliverable = relationship("Deliverable", back_populates="sections")
    template_section = relationship("TemplateSection", back_populates="deliverable_sections")

"""
SQLAlchemy модели для всех таблиц системы.
Соответствуют схеме Template Graph Architecture с 4 слоями:
- Ideal (идеальные шаблоны)
- Custom (пользовательские шаблоны)
- Source (исходные документы)
- Deliverable (готовые документы)
"""
from sqlalchemy import String, Integer, Text, ForeignKey, DateTime, Boolean
from sqlalchemy.dialects.postgresql import UUID, ARRAY, JSONB
from sqlalchemy.orm import mapped_column, relationship
from sqlalchemy.sql import func, text
from pgvector.sqlalchemy import Vector
from database import Base
import uuid
import enum


# ============================================
# ENUM ТИПЫ
# ============================================

class InputTypeEnum(str, enum.Enum):
    """Тип входных данных для документов-источников."""
    FILE = "file"
    MANUAL_ENTRY = "manual_entry"


class DeliverableSectionStatusEnum(str, enum.Enum):
    """Статус секции готового документа в workflow."""
    EMPTY = "empty"
    DRAFT_AI = "draft_ai"
    IN_PROGRESS = "in_progress"
    REVIEW = "review"
    APPROVED = "approved"


# ============================================
# СЛОЙ "ИДЕАЛЬНЫЕ ШАБЛОНЫ" (Ideal Layer)
# ============================================

class IdealTemplate(Base):
    """
    Модель для таблицы ideal_templates.
    Идеальные шаблоны (System Master Data) - золотые стандарты структур документов.
    """
    __tablename__ = "ideal_templates"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = mapped_column(String, nullable=False)  # например, "Protocol_EAEU", "CSR_ICH_E3"
    version = mapped_column(Integer, nullable=False, default=1)
    is_active = mapped_column(Boolean, nullable=False, default=True)
    group_id = mapped_column(UUID(as_uuid=True), nullable=True)  # для группировки версий
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    sections = relationship("IdealSection", back_populates="template", cascade="all, delete-orphan")
    custom_templates = relationship("CustomTemplate", back_populates="base_ideal_template")


class IdealSection(Base):
    """
    Модель для таблицы ideal_sections.
    Секции идеальных шаблонов (золотые стандарты структур).
    """
    __tablename__ = "ideal_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    template_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_templates.id", ondelete="CASCADE"), nullable=False)
    parent_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="CASCADE"), nullable=True)
    title = mapped_column(Text, nullable=False)
    order_index = mapped_column(Integer, nullable=False, default=0)
    embedding = mapped_column(Vector(1536), nullable=True)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    template = relationship("IdealTemplate", back_populates="sections")
    parent = relationship("IdealSection", remote_side=[id], backref="children")
    target_mappings = relationship("IdealMapping", foreign_keys="IdealMapping.target_ideal_section_id", back_populates="target_section")
    source_mappings = relationship("IdealMapping", foreign_keys="IdealMapping.source_ideal_section_id", back_populates="source_section")
    custom_sections = relationship("CustomSection", back_populates="ideal_section")
    custom_mappings = relationship("CustomMapping", foreign_keys="CustomMapping.source_ideal_section_id", back_populates="source_ideal_section")
    target_custom_mappings = relationship("CustomMapping", foreign_keys="CustomMapping.target_ideal_section_id", back_populates="target_ideal_section")


class IdealMapping(Base):
    """
    Модель для таблицы ideal_mappings.
    Правила переноса данных между идеальными секциями.
    """
    __tablename__ = "ideal_mappings"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    target_ideal_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="CASCADE"), nullable=False)
    source_ideal_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="CASCADE"), nullable=False)
    instruction = mapped_column(Text, nullable=True)  # промпт для трансформации
    order_index = mapped_column(Integer, nullable=False, default=0)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    target_section = relationship("IdealSection", foreign_keys=[target_ideal_section_id], back_populates="target_mappings")
    source_section = relationship("IdealSection", foreign_keys=[source_ideal_section_id], back_populates="source_mappings")


# ============================================
# СЛОЙ "ПОЛЬЗОВАТЕЛЬСКИЕ ШАБЛОНЫ" (Custom Layer)
# ============================================

class CustomTemplate(Base):
    """
    Модель для таблицы custom_templates.
    Пользовательские шаблоны (Configuration) - настройки на основе идеальных шаблонов.
    """
    __tablename__ = "custom_templates"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    base_ideal_template_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_templates.id", ondelete="RESTRICT"), nullable=False)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=True)  # NULL для глобальных шаблонов
    name = mapped_column(String, nullable=False)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    base_ideal_template = relationship("IdealTemplate", back_populates="custom_templates")
    sections = relationship("CustomSection", back_populates="custom_template", cascade="all, delete-orphan")
    source_documents = relationship("SourceDocument", back_populates="template")
    deliverables = relationship("Deliverable", back_populates="template")


class CustomSection(Base):
    """
    Модель для таблицы custom_sections.
    Секции пользовательских шаблонов.
    """
    __tablename__ = "custom_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    custom_template_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_templates.id", ondelete="CASCADE"), nullable=False)
    ideal_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="SET NULL"), nullable=True)
    parent_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_sections.id", ondelete="CASCADE"), nullable=True)
    title = mapped_column(Text, nullable=False)
    order_index = mapped_column(Integer, nullable=False, default=0)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    custom_template = relationship("CustomTemplate", back_populates="sections")
    ideal_section = relationship("IdealSection", back_populates="custom_sections")
    parent = relationship("CustomSection", remote_side=[id], backref="children")
    target_mappings = relationship("CustomMapping", foreign_keys="CustomMapping.target_custom_section_id", back_populates="target_section")
    source_mappings = relationship("CustomMapping", foreign_keys="CustomMapping.source_custom_section_id", back_populates="source_section")
    source_sections = relationship("SourceSection", back_populates="template_section")
    deliverable_sections = relationship("DeliverableSection", back_populates="custom_section")


class CustomMapping(Base):
    """
    Модель для таблицы custom_mappings.
    Правила переноса данных для пользовательских шаблонов.
    """
    __tablename__ = "custom_mappings"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    target_custom_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_sections.id", ondelete="CASCADE"), nullable=False)
    target_ideal_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="CASCADE"), nullable=True)
    source_custom_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_sections.id", ondelete="CASCADE"), nullable=True)
    source_ideal_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("ideal_sections.id", ondelete="CASCADE"), nullable=True)
    instruction = mapped_column(Text, nullable=True)  # промпт для трансформации
    order_index = mapped_column(Integer, nullable=False, default=0)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    target_section = relationship("CustomSection", foreign_keys=[target_custom_section_id], back_populates="target_mappings")
    target_ideal_section = relationship("IdealSection", foreign_keys=[target_ideal_section_id], back_populates="target_custom_mappings")
    source_section = relationship("CustomSection", foreign_keys=[source_custom_section_id], back_populates="source_mappings")
    source_ideal_section = relationship("IdealSection", foreign_keys=[source_ideal_section_id], back_populates="custom_mappings")


# ============================================
# СЛОЙ "ИСТОЧНИКИ" (Source Layer)
# ============================================

class SourceDocument(Base):
    """
    Модель для таблицы source_documents.
    Метаданные исходных документов с поддержкой версионирования.
    """
    __tablename__ = "source_documents"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    template_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_templates.id", ondelete="SET NULL"), nullable=True)
    name = mapped_column(String, nullable=False)
    storage_path = mapped_column(String, nullable=False)  # устаревшее, использовать file_path
    file_path = mapped_column(String, nullable=True)  # путь к файлу (может быть NULL для ручного ввода)
    input_type = mapped_column(String, nullable=True, default="file")  # ENUM: 'file', 'manual_entry'
    doc_type = mapped_column(String, nullable=True)  # 'Protocol', 'SAP', 'Brochure'
    status = mapped_column(String, nullable=False, default="uploading")  # 'uploading', 'indexed', 'error'
    parent_document_id = mapped_column(UUID(as_uuid=True), ForeignKey("source_documents.id", ondelete="SET NULL"), nullable=True)
    version_label = mapped_column(String, nullable=True)  # например "v1.0", "v2.1"
    is_current_version = mapped_column(Boolean, nullable=True, default=True)
    parsing_metadata = mapped_column(JSONB, nullable=True, default={})  # Техн. метрики (время, кол-во страниц)
    parsing_quality_score = mapped_column(Integer, nullable=True)  # Оценка пользователя (1-5)
    parsing_quality_comment = mapped_column(Text, nullable=True)  # Комментарий к ошибке
    detected_tables_count = mapped_column(Integer, nullable=False, default=0)
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    template = relationship("CustomTemplate", back_populates="source_documents")
    parent_document = relationship("SourceDocument", remote_side=[id], backref="child_versions")
    sections = relationship("SourceSection", back_populates="source_document", cascade="all, delete-orphan")


class SourceSection(Base):
    """
    Модель для таблицы source_sections.
    Хранит структурированные секции исходных документов (Inputs) с поддержкой векторов для гибридного поиска.
    """
    __tablename__ = "source_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_id = mapped_column(UUID(as_uuid=True), ForeignKey("source_documents.id", ondelete="CASCADE"), nullable=False)
    custom_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_sections.id", ondelete="SET NULL"), nullable=True)
    
    # Структурные поля
    section_number = mapped_column(String, nullable=True)  # например "3.1.2"
    header = mapped_column(Text, nullable=True)  # например "Критерии включения"
    page_number = mapped_column(Integer, nullable=True)
    
    # Контент
    content_text = mapped_column(Text, nullable=True)  # Чистый текст для поиска
    content_markdown = mapped_column(Text, nullable=True)  # Текст с разметкой таблиц (для LLM)
    
    # Вектор для гибридного поиска
    embedding = mapped_column(Vector(1536), nullable=True)
    
    # Классификация
    classification_confidence = mapped_column(Integer, nullable=True)  # FLOAT в БД, но используем Integer для совместимости
    
    # Координаты текста для подсветки в PDF
    bbox = mapped_column(JSONB, nullable=True)  # {"page": 1, "x": 100, "y": 200, "w": 300, "h": 50}
    
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    source_document = relationship("SourceDocument", back_populates="sections")
    template_section = relationship("CustomSection", back_populates="source_sections")


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
    Готовые документы (Outputs/Deliverables), созданные на основе пользовательских шаблонов.
    """
    __tablename__ = "deliverables"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    template_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_templates.id", ondelete="RESTRICT"), nullable=False)
    title = mapped_column(Text, nullable=False)
    status = mapped_column(String, nullable=False, default="draft")  # 'draft', 'final'
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    template = relationship("CustomTemplate", back_populates="deliverables")
    sections = relationship("DeliverableSection", back_populates="deliverable", cascade="all, delete-orphan")


class DeliverableSection(Base):
    """
    Модель для таблицы deliverable_sections.
    Секции готовых документов (Outputs) с контентом для редактора, workflow статусами и блокировками.
    """
    __tablename__ = "deliverable_sections"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    deliverable_id = mapped_column(UUID(as_uuid=True), ForeignKey("deliverables.id", ondelete="CASCADE"), nullable=False)
    custom_section_id = mapped_column(UUID(as_uuid=True), ForeignKey("custom_sections.id", ondelete="RESTRICT"), nullable=False)
    parent_id = mapped_column(UUID(as_uuid=True), ForeignKey("deliverable_sections.id", ondelete="CASCADE"), nullable=True)
    content_html = mapped_column(Text, nullable=True)  # HTML контент для редактора Tiptap
    status = mapped_column(String, nullable=False, default="empty")  # ENUM: 'empty', 'draft_ai', 'in_progress', 'review', 'approved'
    locked_by_user_id = mapped_column(UUID(as_uuid=True), nullable=True)  # FK to auth.users (cross-schema reference)
    locked_at = mapped_column(DateTime(timezone=True), nullable=True)
    used_source_section_ids = mapped_column(ARRAY(UUID(as_uuid=True)), nullable=False, server_default=text("ARRAY[]::UUID[]"))  # Массив ссылок на source_sections
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    
    # Relationships
    deliverable = relationship("Deliverable", back_populates="sections")
    custom_section = relationship("CustomSection", back_populates="deliverable_sections")
    parent = relationship("DeliverableSection", remote_side=[id], backref="children")
    history = relationship("DeliverableSectionHistory", back_populates="section", cascade="all, delete-orphan")


class DeliverableSectionHistory(Base):
    """
    Модель для таблицы deliverable_section_history.
    История изменений секций готовых документов (audit trail).
    """
    __tablename__ = "deliverable_section_history"
    
    id = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    section_id = mapped_column(UUID(as_uuid=True), ForeignKey("deliverable_sections.id", ondelete="CASCADE"), nullable=False)
    content_snapshot = mapped_column(Text, nullable=False)  # снимок HTML контента на момент изменения
    changed_by_user_id = mapped_column(UUID(as_uuid=True), nullable=False)  # FK to auth.users (cross-schema reference)
    change_reason = mapped_column(Text, nullable=True)  # причина изменения (например, "AI generation", "Manual edit")
    created_at = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Relationships
    section = relationship("DeliverableSection", back_populates="history")

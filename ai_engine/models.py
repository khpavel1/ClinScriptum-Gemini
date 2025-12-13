"""
SQLAlchemy модели для таблиц document_sections и study_globals.
Соответствуют схеме из docs/00_MASTER_ARCH.md и docs/02_DATA_RAG.md.
"""
from sqlalchemy import Column, String, Integer, Text, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from database import Base
import uuid


class DocumentSection(Base):
    """
    Модель для таблицы document_sections.
    Хранит структурированные секции документов с поддержкой векторов для гибридного поиска.
    """
    __tablename__ = "document_sections"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_id = Column(UUID(as_uuid=True), ForeignKey("source_documents.id", ondelete="CASCADE"), nullable=False)
    
    # Структурные поля
    section_number = Column(String, nullable=True)  # например "3.1.2"
    header = Column(Text, nullable=True)  # например "Критерии включения"
    page_number = Column(Integer, nullable=True)
    
    # Контент
    content_text = Column(Text, nullable=True)  # Чистый текст для поиска
    content_markdown = Column(Text, nullable=True)  # Текст с разметкой таблиц (для LLM)
    
    # Вектор для гибридного поиска (опционально)
    # Примечание: для работы с pgvector нужно установить расширение vector
    # embedding = Column(Vector(1536), nullable=True)  # Раскомментировать после установки pgvector
    
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Связи (опционально, если нужны relationships)
    # source_document = relationship("SourceDocument", back_populates="sections")


class StudyGlobal(Base):
    """
    Модель для таблицы study_globals.
    Хранит глобальные переменные исследования (Паспорт исследования).
    """
    __tablename__ = "study_globals"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    variable_name = Column(String, nullable=True)  # "Phase", "Drug_Name", "Primary_Endpoint" и т.д.
    variable_value = Column(Text, nullable=True)  # Значение переменной
    source_section_id = Column(UUID(as_uuid=True), ForeignKey("document_sections.id", ondelete="SET NULL"), nullable=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    
    # Связи (опционально, если нужны relationships)
    # project = relationship("Project", back_populates="globals")
    # source_section = relationship("DocumentSection", back_populates="globals")

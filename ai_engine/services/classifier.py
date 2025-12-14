"""
Сервис для классификации секций документов.
Привязывает реальный текст к секциям шаблона через векторный поиск.
"""
from typing import Optional
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.sql import func
from pgvector.sqlalchemy import Vector

from models import CustomSection, IdealSection
from services.llm import LLMClient


class SectionClassifier:
    """
    Классификатор секций документов.
    Использует векторный поиск для привязки текста к шаблону.
    """
    
    def __init__(self, llm_client: LLMClient):
        """
        Инициализация классификатора.
        
        Args:
            llm_client: Клиент для работы с LLM и эмбеддингами
        """
        self.llm_client = llm_client
        self.similarity_threshold = 0.85  # Порог cosine similarity
    
    async def classify_section(
        self,
        session: AsyncSession,
        header_text: str,
        template_id: UUID
    ) -> Optional[UUID]:
        """
        Классифицирует секцию документа, привязывая её к секции пользовательского шаблона.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            header_text: Текст заголовка секции документа
            template_id: UUID пользовательского шаблона (custom_template_id)
            
        Returns:
            UUID секции пользовательского шаблона (custom_section_id), если найдена подходящая (similarity > 0.85), иначе None
        """
        if not header_text or not header_text.strip():
            return None
        
        # Получаем эмбеддинг для заголовка
        try:
            header_embedding = await self.llm_client.get_embedding(header_text.strip())
        except Exception as e:
            # Если не удалось получить эмбеддинг, возвращаем None
            print(f"Ошибка при получении эмбеддинга для заголовка '{header_text}': {str(e)}")
            return None
        
        # Ищем ближайшую секцию в пользовательском шаблоне через векторный поиск
        # Сначала ищем в custom_sections, если нет эмбеддингов - ищем через ideal_sections
        # Используем cosine similarity (1 - cosine_distance)
        query = (
            select(
                CustomSection.id,
                CustomSection.title,
                # Вычисляем cosine similarity через ideal_section.embedding
                (1 - func.cosine_distance(IdealSection.embedding, header_embedding)).label("similarity")
            )
            .join(IdealSection, CustomSection.ideal_section_id == IdealSection.id)
            .where(
                CustomSection.custom_template_id == template_id,
                IdealSection.embedding.isnot(None)
            )
            .order_by(
                func.cosine_distance(IdealSection.embedding, header_embedding)
            )
            .limit(1)
        )
        
        result = await session.execute(query)
        row = result.first()
        
        if row and row.similarity >= self.similarity_threshold:
            return row.id
        
        return None

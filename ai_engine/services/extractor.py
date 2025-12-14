"""
Сервис для извлечения глобальных переменных исследования (Паспорт исследования).
Использует LLM для извлечения структурированных данных из секций документов.
"""
import json
from typing import Dict, List, Optional
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from models import SourceSection, StudyGlobal, SourceDocument
from services.llm import LLMClient


class GlobalExtractor:
    """
    Экстрактор глобальных переменных исследования.
    Извлекает Phase, Drug Name, Population и другие метаданные из документов.
    """
    
    def __init__(self, llm_client: LLMClient):
        """
        Инициализация экстрактора.
        
        Args:
            llm_client: Клиент для работы с LLM
        """
        self.llm_client = llm_client
    
    async def extract_globals(
        self,
        session: AsyncSession,
        project_id: UUID
    ) -> Dict[str, str]:
        """
        Извлекает глобальные переменные исследования из документов проекта.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            
        Returns:
            Словарь с глобальными переменными: {variable_name: variable_value}
        """
        # Ищем секции с "Synopsis" в заголовке или первые 5 секций документов проекта
        # Используем прямую фильтрацию по заголовкам, без привязки к устаревшим шаблонам
        sections_query = (
            select(SourceSection)
            .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
            .where(
                SourceDocument.project_id == project_id,
                SourceDocument.is_current_version == True
            )
            .where(
                SourceSection.header.ilike("%synopsis%")
            )
            .limit(5)
        )
        
        # Если не найдено секций с Synopsis, берем первые 5 секций документов проекта
        sections_result = await session.execute(sections_query)
        sections = sections_result.scalars().all()
        
        if not sections:
            sections_query = (
                select(SourceSection)
                .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
                .where(
                    SourceDocument.project_id == project_id,
                    SourceDocument.is_current_version == True
                )
                .order_by(SourceSection.section_number)
                .limit(5)
            )
        
        sections_result = await session.execute(sections_query)
        sections = sections_result.scalars().all()
        
        if not sections:
            return {}
        
        # Собираем текст из секций
        combined_text = "\n\n".join([
            f"## {section.header}\n{section.content_markdown or section.content_text or ''}"
            for section in sections
        ])
        
        # Формируем промпт для LLM
        system_prompt = """Ты - эксперт по медицинским исследованиям. 
Твоя задача - извлечь структурированные данные из текста протокола исследования.
Верни результат в формате JSON с ключами: Phase, Drug_Name, Population, Primary_Endpoint, Secondary_Endpoints, Study_Design, Inclusion_Criteria, Exclusion_Criteria.
Если какое-то поле не найдено, верни null для этого поля."""
        
        user_prompt = f"""Извлеки глобальные переменные исследования из следующего текста:

{combined_text}

Верни результат в формате JSON."""
        
        # Генерируем ответ через LLM
        try:
            response_text = await self.llm_client.generate_text(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=0.3
            )
            
            # Парсим JSON из ответа
            # LLM может вернуть JSON в markdown блоке или просто JSON
            json_text = response_text.strip()
            if json_text.startswith("```json"):
                json_text = json_text[7:]
            if json_text.startswith("```"):
                json_text = json_text[3:]
            if json_text.endswith("```"):
                json_text = json_text[:-3]
            json_text = json_text.strip()
            
            globals_dict = json.loads(json_text)
            
            # Удаляем старые записи проекта
            delete_result = await session.execute(
                select(StudyGlobal).where(StudyGlobal.project_id == project_id)
            )
            old_globals = delete_result.scalars().all()
            for old_global in old_globals:
                await session.delete(old_global)
            
            # Сохраняем новые глобальные переменные
            for variable_name, variable_value in globals_dict.items():
                if variable_value is not None:
                    # Находим source_section_id из первой секции
                    source_section_id = sections[0].id if sections else None
                    
                    global_var = StudyGlobal(
                        project_id=project_id,
                        variable_name=variable_name,
                        variable_value=str(variable_value),
                        source_section_id=source_section_id
                    )
                    session.add(global_var)
            
            await session.flush()
            
            return globals_dict
            
        except json.JSONDecodeError as e:
            print(f"Ошибка при парсинге JSON из ответа LLM: {str(e)}")
            print(f"Ответ LLM: {response_text}")
            return {}
        except Exception as e:
            print(f"Ошибка при извлечении глобальных переменных: {str(e)}")
            return {}

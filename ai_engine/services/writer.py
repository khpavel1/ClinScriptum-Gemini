"""
Сервис для генерации секций документов на основе Template Graph.
Использует граф связей между секциями для генерации целевых секций.
"""
from typing import List, Optional, Tuple
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, desc
from pydantic import BaseModel

from models import (
    SectionMapping, SourceSection, StudyGlobal, 
    TemplateSection, SourceDocument, DeliverableSection
)
from services.llm import LLMClient


class SectionWriter:
    """
    Генератор секций документов.
    Использует Template Graph для генерации целевых секций на основе исходных.
    """
    
    def __init__(self, llm_client: LLMClient):
        """
        Инициализация генератора.
        
        Args:
            llm_client: Клиент для работы с LLM
        """
        self.llm_client = llm_client
    
    async def generate_target_section(
        self,
        session: AsyncSession,
        project_id: UUID,
        target_template_section_id: UUID,
        deliverable_id: UUID
    ) -> str:
        """
        Генерирует целевую секцию документа на основе Template Graph.
        
        Процесс:
        1. Находит правила (section_mappings) для целевой секции
        2. Находит исходные секции документов проекта в таблице source_sections
        3. Собирает контекст (глобальные переменные + исходные секции)
        4. Генерирует текст через LLM с учетом инструкций трансформации
        5. Сохраняет результат в таблицу deliverable_sections
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            target_template_section_id: UUID целевой секции шаблона
            deliverable_id: UUID документа (deliverable), в который сохраняется секция
            
        Returns:
            Сгенерированный текст секции в формате Markdown
            
        Raises:
            ValueError: Если целевая секция не найдена
        """
        # Получаем информацию о целевой секции
        target_section_result = await session.execute(
            select(TemplateSection).where(TemplateSection.id == target_template_section_id)
        )
        target_section = target_section_result.scalar_one_or_none()
        
        if not target_section:
            raise ValueError(f"Целевая секция шаблона не найдена: {target_template_section_id}")
        
        # Шаг 1: Находим правила (section_mappings) для целевой секции
        mappings_result = await session.execute(
            select(SectionMapping).where(
                SectionMapping.target_section_id == target_template_section_id
            )
        )
        mappings = mappings_result.scalars().all()
        
        if not mappings:
            # Если нет правил, создаем пустую секцию или возвращаем описание
            empty_content = f"# {target_section.title}\n\n{target_section.description or 'Секция требует заполнения.'}"
            # Находим или создаем deliverable_section
            deliverable_section_result = await session.execute(
                select(DeliverableSection).where(
                    and_(
                        DeliverableSection.deliverable_id == deliverable_id,
                        DeliverableSection.template_section_id == target_template_section_id
                    )
                )
            )
            deliverable_section = deliverable_section_result.scalar_one_or_none()
            
            if not deliverable_section:
                deliverable_section = DeliverableSection(
                    deliverable_id=deliverable_id,
                    template_section_id=target_template_section_id,
                    content_html=empty_content,
                    status="generated",
                    used_source_section_ids=[]
                )
                session.add(deliverable_section)
            else:
                deliverable_section.content_html = empty_content
                deliverable_section.status = "generated"
                deliverable_section.used_source_section_ids = []
            
            await session.flush()
            return empty_content
        
        # Шаг 2: Для каждого правила находим исходные секции документов проекта
        source_texts: List[str] = []
        instructions: List[str] = []
        used_source_section_ids: List[UUID] = []
        
        for mapping in mappings:
            # Находим документные секции, привязанные к исходной секции шаблона
            source_sections_result = await session.execute(
                select(SourceSection)
                .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
                .where(
                    and_(
                        SourceDocument.project_id == project_id,
                        SourceSection.template_section_id == mapping.source_section_id
                    )
                )
            )
            source_sections = source_sections_result.scalars().all()
            
            # Собираем тексты исходных секций и их ID
            for section in source_sections:
                section_text = f"## {section.header}\n\n{section.content_markdown or section.content_text or ''}"
                source_texts.append(section_text)
                used_source_section_ids.append(section.id)
                
                # Сохраняем инструкцию трансформации
                if mapping.instruction:
                    instructions.append(f"Инструкция для секции '{section.header}': {mapping.instruction}")
        
        if not source_texts:
            # Если нет исходных секций, создаем секцию с описанием
            empty_content = f"# {target_section.title}\n\n{target_section.description or 'Исходные данные для генерации не найдены.'}"
            # Находим или создаем deliverable_section
            deliverable_section_result = await session.execute(
                select(DeliverableSection).where(
                    and_(
                        DeliverableSection.deliverable_id == deliverable_id,
                        DeliverableSection.template_section_id == target_template_section_id
                    )
                )
            )
            deliverable_section = deliverable_section_result.scalar_one_or_none()
            
            if not deliverable_section:
                deliverable_section = DeliverableSection(
                    deliverable_id=deliverable_id,
                    template_section_id=target_template_section_id,
                    content_html=empty_content,
                    status="generated",
                    used_source_section_ids=[]
                )
                session.add(deliverable_section)
            else:
                deliverable_section.content_html = empty_content
                deliverable_section.status = "generated"
                deliverable_section.used_source_section_ids = []
            
            await session.flush()
            return empty_content
        
        # Шаг 3: Загружаем глобальные переменные (Паспорт исследования)
        globals_result = await session.execute(
            select(StudyGlobal).where(StudyGlobal.project_id == project_id)
        )
        globals_list = globals_result.scalars().all()
        
        # Формируем строку с глобальными переменными
        globals_text = "## Паспорт исследования\n\n"
        for global_var in globals_list:
            globals_text += f"- **{global_var.variable_name}**: {global_var.variable_value}\n"
        
        # Шаг 4: Формируем промпты для LLM
        system_prompt = f"""Ты - эксперт по медицинской документации.
Твоя задача - сгенерировать секцию документа на основе исходных данных и инструкций.

Целевая секция: {target_section.title}
Описание секции: {target_section.description or 'Нет описания'}

Используй следующие исходные данные и инструкции для генерации текста.
Важно: следуй инструкциям трансформации, если они указаны."""
        
        # Объединяем исходные тексты
        source_text_combined = "\n\n---\n\n".join(source_texts)
        
        # Формируем инструкции
        instructions_text = "\n".join(instructions) if instructions else "Используй исходные данные как есть."
        
        user_prompt = f"""Глобальные переменные исследования:
{globals_text}

Исходные секции документов:
{source_text_combined}

Инструкции по трансформации:
{instructions_text}

Сгенерируй текст для секции "{target_section.title}" в формате Markdown.
Текст должен быть профессиональным, структурированным и соответствовать медицинским стандартам."""
        
        # Шаг 5: Генерируем текст через LLM
        try:
            generated_text = await self.llm_client.generate_text(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=0.7,
                max_tokens=2000
            )
            
            # Убеждаемся, что текст начинается с заголовка
            if not generated_text.strip().startswith("#"):
                generated_text = f"# {target_section.title}\n\n{generated_text}"
            
            # Шаг 6: Сохраняем результат в таблицу deliverable_sections
            # Находим или создаем deliverable_section
            deliverable_section_result = await session.execute(
                select(DeliverableSection).where(
                    and_(
                        DeliverableSection.deliverable_id == deliverable_id,
                        DeliverableSection.template_section_id == target_template_section_id
                    )
                )
            )
            deliverable_section = deliverable_section_result.scalar_one_or_none()
            
            if not deliverable_section:
                # Создаем новую секцию
                deliverable_section = DeliverableSection(
                    deliverable_id=deliverable_id,
                    template_section_id=target_template_section_id,
                    content_html=generated_text,
                    status="generated",
                    used_source_section_ids=used_source_section_ids
                )
                session.add(deliverable_section)
            else:
                # Обновляем существующую секцию
                deliverable_section.content_html = generated_text
                deliverable_section.status = "generated"
                deliverable_section.used_source_section_ids = used_source_section_ids
            
            await session.flush()
            
            return generated_text
            
        except Exception as e:
            raise Exception(f"Ошибка при генерации секции: {str(e)}")


class GenerationResult(BaseModel):
    """
    Результат генерации секции документа.
    
    Attributes:
        content: Сгенерированный текст секции в формате Markdown
        used_source_section_ids: Список UUID исходных секций, использованных для генерации
        mapping_logic_used: Описание правила маппинга, которое было применено
    """
    content: str
    used_source_section_ids: List[UUID]
    mapping_logic_used: str


class ContentWriter:
    """
    Сервис генерации контента на основе Template Graph и глобального контекста.
    Отвечает за генерацию черновика раздела (например, для CSR) на основе данных из Протокола.
    """
    
    def __init__(self, llm_client: LLMClient):
        """
        Инициализация генератора контента.
        
        Args:
            llm_client: Клиент для работы с LLM
        """
        self.llm_client = llm_client
    
    async def generate_section_draft(
        self,
        project_id: UUID,
        target_template_section_id: UUID,
        session: AsyncSession
    ) -> GenerationResult:
        """
        Генерирует черновик раздела на основе данных из Протокола, используя Граф Шаблонов и Глобальный контекст.
        
        Алгоритм:
        1. Сбор Глобального Контекста ("Паспорт Исследования") из study_globals
        2. Обход Графа (Поиск правил) в section_mappings
        3. Поиск Реального Контента (Retrieval) в source_sections
        4. Сборка Промпта (Prompt Engineering)
        5. Генерация и Ответ через LLM
        
        Args:
            project_id: UUID проекта
            target_template_section_id: UUID целевой секции шаблона
            session: SQLAlchemy асинхронная сессия
            
        Returns:
            GenerationResult с сгенерированным контентом и метаданными
            
        Raises:
            ValueError: Если не найдены правила маппинга или исходный контент
        """
        # Step 1: Сбор Глобального Контекста ("Паспорт Исследования")
        global_context_string = await self._collect_global_context(session, project_id)
        
        # Step 2: Обход Графа (Поиск правил)
        mappings = await self._find_mapping_rules(session, target_template_section_id)
        
        if not mappings:
            raise ValueError("No mapping rules found for this section")
        
        # Step 3: Поиск Реального Контента (Retrieval)
        source_content_data = await self._retrieve_source_content(
            session, project_id, mappings
        )
        
        if not source_content_data:
            raise ValueError(
                "Source content not found. Please upload and parse the Protocol first."
            )
        
        # Step 4: Сборка Промпта (Prompt Engineering)
        system_prompt, user_prompt = self._build_prompts(
            global_context_string,
            source_content_data,
            mappings
        )
        
        # Step 5: Генерация и Ответ
        try:
            generated_content = await self.llm_client.generate_text(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=0.7,
                max_tokens=3000
            )
        except Exception as e:
            raise Exception(f"Ошибка при генерации контента через LLM: {str(e)}")
        
        # Формируем описание использованного правила маппинга
        mapping_descriptions = []
        for mapping in mappings:
            desc = f"Mapping from section {mapping.source_section_id} "
            desc += f"(type: {mapping.relationship_type})"
            if mapping.instruction:
                desc += f" with instruction: {mapping.instruction[:100]}"
            mapping_descriptions.append(desc)
        
        mapping_logic_used = "; ".join(mapping_descriptions)
        
        return GenerationResult(
            content=generated_content,
            used_source_section_ids=source_content_data["section_ids"],
            mapping_logic_used=mapping_logic_used
        )
    
    async def _collect_global_context(
        self,
        session: AsyncSession,
        project_id: UUID
    ) -> str:
        """
        Собирает глобальный контекст исследования из study_globals.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            
        Returns:
            Строка с глобальными переменными в формате JSON или Bullet-points
        """
        result = await session.execute(
            select(StudyGlobal).where(StudyGlobal.project_id == project_id)
        )
        globals_list = result.scalars().all()
        
        if not globals_list:
            return "Глобальные переменные исследования не найдены."
        
        # Формируем строку в формате Bullet-points
        context_lines = []
        for global_var in globals_list:
            if global_var.variable_name and global_var.variable_value:
                context_lines.append(
                    f"- **{global_var.variable_name}**: {global_var.variable_value}"
                )
        
        return "\n".join(context_lines) if context_lines else "Глобальные переменные исследования не найдены."
    
    async def _find_mapping_rules(
        self,
        session: AsyncSession,
        target_template_section_id: UUID
    ) -> List[SectionMapping]:
        """
        Находит все правила маппинга для целевой секции.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            target_template_section_id: UUID целевой секции шаблона
            
        Returns:
            Список правил маппинга (SectionMapping)
        """
        result = await session.execute(
            select(SectionMapping).where(
                SectionMapping.target_section_id == target_template_section_id
            )
        )
        return result.scalars().all()
    
    async def _retrieve_source_content(
        self,
        session: AsyncSession,
        project_id: UUID,
        mappings: List[SectionMapping]
    ) -> Optional[dict]:
        """
        Находит реальные тексты из документов проекта, соответствующие source_section_id из маппингов.
        
        Для каждого маппинга находит секции документов:
        - Документ должен принадлежать project_id
        - template_section_id должен совпадать с source_section_id из маппинга
        - Если найдено несколько версий, берется самая свежая (по created_at документа)
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            mappings: Список правил маппинга
            
        Returns:
            Словарь с ключами:
            - "content": объединенный контент всех найденных секций
            - "headers": список заголовков
            - "section_ids": список UUID использованных секций
            Или None, если контент не найден
        """
        all_sections = []
        all_section_ids = []
        
        for mapping in mappings:
            # Находим секции документов, привязанные к source_section_id
            # Сортируем по дате создания документа (самый свежий первым)
            result = await session.execute(
                select(SourceSection, SourceDocument)
                .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
                .where(
                    and_(
                        SourceDocument.project_id == project_id,
                        SourceSection.template_section_id == mapping.source_section_id
                    )
                )
                .order_by(desc(SourceDocument.created_at))
            )
            
            # Берем только самую свежую версию для каждого source_section_id
            # (первая запись после сортировки по created_at DESC)
            rows = result.all()
            if rows:
                doc_section, source_doc = rows[0]  # Берем самую свежую версию
                all_sections.append((doc_section, mapping))
                all_section_ids.append(doc_section.id)
        
        if not all_sections:
            return None
        
        # Формируем контент из найденных секций
        content_parts = []
        headers = []
        
        for doc_section, mapping in all_sections:
            header = doc_section.header or f"Section {doc_section.section_number or 'N/A'}"
            headers.append(header)
            
            # Используем content_markdown, если есть, иначе content_text
            content = doc_section.content_markdown or doc_section.content_text or ""
            
            if content:
                content_parts.append(f"**Заголовок:** {header}\n\n**Контент:**\n{content}")
        
        combined_content = "\n\n---\n\n".join(content_parts)
        
        return {
            "content": combined_content,
            "headers": headers,
            "section_ids": all_section_ids
        }
    
    def _build_prompts(
        self,
        global_context_string: str,
        source_content_data: dict,
        mappings: List[SectionMapping]
    ) -> Tuple[str, str]:
        """
        Формирует промпты для LLM (System и User сообщения).
        
        Args:
            global_context_string: Строка с глобальными переменными исследования
            source_content_data: Словарь с исходным контентом (из _retrieve_source_content)
            mappings: Список правил маппинга
            
        Returns:
            Кортеж (system_prompt, user_prompt)
        """
        # Формируем инструкции из всех маппингов
        instructions = []
        for mapping in mappings:
            if mapping.instruction:
                instructions.append(mapping.instruction)
        
        instruction_text = "\n".join(instructions) if instructions else (
            "Используй исходные данные для генерации текста. "
            "Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. "
            "Глаголы ставь в прошедшее время, так как исследование завершено."
        )
        
        # System Message
        system_prompt = f"""Ты профессиональный медицинский писатель.
Твоя задача — написать раздел клинического документа.

ГЛОБАЛЬНЫЕ ДАННЫЕ ИССЛЕДОВАНИЯ (Строго соблюдай эти факты):
{global_context_string}

Важно: Используй только факты из глобальных данных исследования. Не придумывай информацию."""
        
        # User Message
        user_prompt = f"""ИСХОДНЫЕ ДАННЫЕ (Из Протокола/SAP):

{source_content_data["content"]}

ИНСТРУКЦИЯ:
{instruction_text}

(Дополнительно: Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. Глаголы ставь в прошедшее время, так как исследование завершено.)

Сгенерируй только текст итогового раздела (в формате Markdown)."""
        
        return system_prompt, user_prompt

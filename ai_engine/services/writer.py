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
    CustomSection, CustomMapping, IdealMapping, SourceSection, StudyGlobal, 
    SourceDocument, DeliverableSection, Deliverable, DeliverableSectionHistory
)
from services.llm import LLMClient


class Writer:
    """
    Сервис для генерации секций документов на основе Template Graph.
    Использует граф связей между секциями для генерации целевых секций.
    """
    
    def __init__(self, llm_client: LLMClient):
        """
        Инициализация генератора.
        
        Args:
            llm_client: Клиент для работы с LLM
        """
        self.llm_client = llm_client
    
    async def generate_section(
        self,
        session: AsyncSession,
        deliverable_section_id: UUID,
        changed_by_user_id: UUID
    ) -> str:
        """
        Генерирует секцию документа на основе Template Graph.
        
        Процесс:
        1. Context Resolution: Находит правила маппинга (custom_mappings или ideal_mappings)
        2. Data Retrieval: Находит исходные секции документов с фильтром is_current_version = TRUE
        3. Generation: Формирует промпт, вызывает LLM, обновляет deliverable_sections и создает историю
        
        Args:
            session: SQLAlchemy асинхронная сессия
            deliverable_section_id: UUID секции deliverable для генерации
            changed_by_user_id: UUID пользователя, инициировавшего генерацию (для истории)
            
        Returns:
            Сгенерированный текст секции в формате HTML/Markdown
            
        Raises:
            ValueError: Если секция не найдена или нет данных для генерации
        """
        # Получаем deliverable_section с загруженными связями
        deliverable_section_result = await session.execute(
            select(DeliverableSection)
            .where(DeliverableSection.id == deliverable_section_id)
        )
        deliverable_section = deliverable_section_result.scalar_one_or_none()
        
        if not deliverable_section:
            raise ValueError(f"Deliverable section not found: {deliverable_section_id}")
        
        # Получаем custom_section
        custom_section_result = await session.execute(
            select(CustomSection).where(CustomSection.id == deliverable_section.custom_section_id)
        )
        custom_section = custom_section_result.scalar_one_or_none()
        
        if not custom_section:
            raise ValueError(f"Custom section not found: {deliverable_section.custom_section_id}")
        
        # Получаем project_id через deliverable
        deliverable_result = await session.execute(
            select(Deliverable).where(Deliverable.id == deliverable_section.deliverable_id)
        )
        deliverable = deliverable_result.scalar_one_or_none()
        
        if not deliverable:
            raise ValueError(f"Deliverable not found: {deliverable_section.deliverable_id}")
        
        project_id = deliverable.project_id
        
        # Step 1: Context Resolution (Поиск правил)
        mappings, instructions = await self._resolve_context(session, custom_section)
        
        if not mappings:
            # Если нет правил, создаем пустую секцию
            empty_content = f"<h1>{custom_section.title}</h1><p>Секция требует заполнения.</p>"
            await self._update_deliverable_section(
                session, deliverable_section, empty_content, [], changed_by_user_id
            )
            return empty_content
        
        # Step 2: Data Retrieval (Фильтрация версий)
        source_content_data = await self._retrieve_source_sections(
            session, project_id, mappings
        )
        
        if not source_content_data or not source_content_data["section_ids"]:
            # Если нет исходных секций, создаем секцию с описанием
            empty_content = f"<h1>{custom_section.title}</h1><p>Исходные данные для генерации не найдены.</p>"
            await self._update_deliverable_section(
                session, deliverable_section, empty_content, [], changed_by_user_id
            )
            return empty_content
        
        # Step 3: Загружаем глобальные переменные
        globals_text = await self._collect_global_context(session, project_id)
        
        # Step 4: Generation - Формируем промпт и вызываем LLM
        system_prompt, user_prompt = self._build_prompts(
            custom_section, globals_text, source_content_data, instructions
        )
        
        try:
            generated_content = await self.llm_client.generate_text(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=0.7,
                max_tokens=3000
            )
            
            # Преобразуем Markdown в HTML (базовое преобразование)
            # В продакшене лучше использовать библиотеку markdown или подобную
            content_html = self._markdown_to_html(generated_content, custom_section.title)
            
            # Step 5: Обновляем deliverable_sections и создаем историю
            await self._update_deliverable_section(
                session,
                deliverable_section,
                content_html,
                source_content_data["section_ids"],
                changed_by_user_id
            )
            
            return content_html
            
        except Exception as e:
            raise Exception(f"Ошибка при генерации секции через LLM: {str(e)}")
    
    async def _resolve_context(
        self,
        session: AsyncSession,
        custom_section: CustomSection
    ) -> Tuple[List, List[str]]:
        """
        Разрешает контекст: находит правила маппинга для custom_section.
        
        Алгоритм:
        1. Начинаем с custom_section
        2. Проверяем custom_mappings где target_custom_section_id = custom_section.id
        3. Если нет - идем по ссылке ideal_section_id и ищем в ideal_mappings
        
        Args:
            session: SQLAlchemy асинхронная сессия
            custom_section: CustomSection для поиска правил
            
        Returns:
            Кортеж (список маппингов, список инструкций)
        """
        mappings = []
        instructions = []
        
        # Проверяем custom_mappings
        custom_mappings_result = await session.execute(
            select(CustomMapping)
            .where(CustomMapping.target_custom_section_id == custom_section.id)
            .order_by(CustomMapping.order_index)
        )
        custom_mappings = custom_mappings_result.scalars().all()
        
        if custom_mappings:
            mappings = custom_mappings
            instructions = [m.instruction for m in custom_mappings if m.instruction]
            return mappings, instructions
        
        # Если нет custom_mappings, идем по ссылке ideal_section_id
        if custom_section.ideal_section_id:
            ideal_mappings_result = await session.execute(
                select(IdealMapping)
                .where(IdealMapping.target_ideal_section_id == custom_section.ideal_section_id)
                .order_by(IdealMapping.order_index)
            )
            ideal_mappings = ideal_mappings_result.scalars().all()
            
            if ideal_mappings:
                mappings = ideal_mappings
                instructions = [m.instruction for m in ideal_mappings if m.instruction]
                return mappings, instructions
        
        return [], []
    
    async def _retrieve_source_sections(
        self,
        session: AsyncSession,
        project_id: UUID,
        mappings: List
    ) -> Optional[dict]:
        """
        Находит исходные секции документов проекта с фильтром is_current_version = TRUE.
        
        Для каждого маппинга находит секции документов:
        - Документ должен принадлежать project_id
        - is_current_version = TRUE (важно: только актуальные версии)
        - custom_section_id должен совпадать с source_custom_section_id
        - Если source_ideal_section_id, находим custom_sections с таким ideal_section_id
        - Обрабатывает manual_entry так же, как обычные файлы (берем текст из секции)
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            mappings: Список правил маппинга (CustomMapping или IdealMapping)
            
        Returns:
            Словарь с ключами:
            - "content": объединенный контент всех найденных секций
            - "section_ids": список UUID использованных секций
            Или None, если контент не найден
        """
        all_sections = []
        all_section_ids = []
        seen_section_ids = set()  # Для избежания дубликатов
        
        for mapping in mappings:
            # Определяем список custom_section_ids для поиска
            custom_section_ids_to_search = []
            
            if isinstance(mapping, CustomMapping):
                if mapping.source_custom_section_id:
                    # Прямая ссылка на custom_section
                    custom_section_ids_to_search = [mapping.source_custom_section_id]
                elif mapping.source_ideal_section_id:
                    # Нужно найти все custom_sections с таким ideal_section_id
                    custom_sections_result = await session.execute(
                        select(CustomSection).where(
                            CustomSection.ideal_section_id == mapping.source_ideal_section_id
                        )
                    )
                    custom_sections = custom_sections_result.scalars().all()
                    custom_section_ids_to_search = [cs.id for cs in custom_sections]
            elif isinstance(mapping, IdealMapping):
                # Для IdealMapping находим все custom_sections с таким ideal_section_id
                custom_sections_result = await session.execute(
                    select(CustomSection).where(
                        CustomSection.ideal_section_id == mapping.source_ideal_section_id
                    )
                )
                custom_sections = custom_sections_result.scalars().all()
                custom_section_ids_to_search = [cs.id for cs in custom_sections]
            else:
                continue
            
            if not custom_section_ids_to_search:
                continue
            
            # Находим секции документов с фильтром is_current_version = TRUE
            # Важно: фильтруем только актуальные версии документов
            result = await session.execute(
                select(SourceSection, SourceDocument)
                .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
                .where(
                    and_(
                        SourceDocument.project_id == project_id,
                        SourceDocument.is_current_version == True,
                        SourceSection.custom_section_id.in_(custom_section_ids_to_search)
                    )
                )
            )
            
            rows = result.all()
            for source_section, source_doc in rows:
                # Избегаем дубликатов
                if source_section.id in seen_section_ids:
                    continue
                seen_section_ids.add(source_section.id)
                
                # Обрабатываем manual_entry так же, как обычные файлы
                # Берем текст из секции независимо от input_type
                all_sections.append((source_section, mapping))
                all_section_ids.append(source_section.id)
        
        if not all_sections:
            return None
        
        # Формируем контент из найденных секций
        content_parts = []
        
        for source_section, mapping in all_sections:
            header = source_section.header or f"Section {source_section.section_number or 'N/A'}"
            
            # Используем content_markdown, если есть, иначе content_text
            # Для manual_entry обрабатываем так же, как для обычных файлов
            content = source_section.content_markdown or source_section.content_text or ""
            
            if content:
                content_parts.append(f"**Заголовок:** {header}\n\n**Контент:**\n{content}")
        
        combined_content = "\n\n---\n\n".join(content_parts)
        
        return {
            "content": combined_content,
            "section_ids": all_section_ids
        }
    
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
            Строка с глобальными переменными в формате Bullet-points
        """
        result = await session.execute(
            select(StudyGlobal).where(StudyGlobal.project_id == project_id)
        )
        globals_list = result.scalars().all()
        
        if not globals_list:
            return "Глобальные переменные исследования не найдены."
        
        context_lines = []
        for global_var in globals_list:
            if global_var.variable_name and global_var.variable_value:
                context_lines.append(
                    f"- **{global_var.variable_name}**: {global_var.variable_value}"
                )
        
        return "\n".join(context_lines) if context_lines else "Глобальные переменные исследования не найдены."
    
    def _build_prompts(
        self,
        custom_section: CustomSection,
        globals_text: str,
        source_content_data: dict,
        instructions: List[str]
    ) -> Tuple[str, str]:
        """
        Формирует промпты для LLM (System и User сообщения).
        
        Args:
            custom_section: Целевая секция шаблона
            globals_text: Строка с глобальными переменными исследования
            source_content_data: Словарь с исходным контентом
            instructions: Список инструкций из маппингов
            
        Returns:
            Кортеж (system_prompt, user_prompt)
        """
        instruction_text = "\n".join(instructions) if instructions else (
            "Используй исходные данные для генерации текста. "
            "Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. "
            "Глаголы ставь в прошедшее время, так как исследование завершено."
        )
        
        # System Message
        system_prompt = f"""Ты профессиональный медицинский писатель.
Твоя задача — написать раздел клинического документа.

ГЛОБАЛЬНЫЕ ДАННЫЕ ИССЛЕДОВАНИЯ (Строго соблюдай эти факты):
{globals_text}

Важно: Используй только факты из глобальных данных исследования. Не придумывай информацию."""
        
        # User Message
        user_prompt = f"""ИСХОДНЫЕ ДАННЫЕ (Из Протокола/SAP):

{source_content_data["content"]}

ИНСТРУКЦИЯ:
{instruction_text}

(Дополнительно: Если видишь таблицу в Markdown, проанализируй её и опиши ключевые данные текстом. Глаголы ставь в прошедшее время, так как исследование завершено.)

Сгенерируй текст для секции "{custom_section.title}" в формате Markdown."""
        
        return system_prompt, user_prompt
    
    def _markdown_to_html(self, markdown_text: str, title: str) -> str:
        """
        Простое преобразование Markdown в HTML.
        В продакшене лучше использовать библиотеку markdown или подобную.
        
        Args:
            markdown_text: Текст в формате Markdown
            title: Заголовок секции
            
        Returns:
            Текст в формате HTML
        """
        # Базовое преобразование Markdown в HTML
        # Обрабатываем заголовки
        lines = markdown_text.split("\n")
        html_lines = []
        in_paragraph = False
        
        for line in lines:
            line_stripped = line.strip()
            
            # Заголовки
            if line_stripped.startswith("# "):
                if in_paragraph:
                    html_lines.append("</p>")
                    in_paragraph = False
                html_lines.append(f"<h1>{line_stripped[2:]}</h1>")
            elif line_stripped.startswith("## "):
                if in_paragraph:
                    html_lines.append("</p>")
                    in_paragraph = False
                html_lines.append(f"<h2>{line_stripped[3:]}</h2>")
            elif line_stripped.startswith("### "):
                if in_paragraph:
                    html_lines.append("</p>")
                    in_paragraph = False
                html_lines.append(f"<h3>{line_stripped[4:]}</h3>")
            elif line_stripped == "":
                # Пустая строка - закрываем параграф
                if in_paragraph:
                    html_lines.append("</p>")
                    in_paragraph = False
            else:
                # Обычный текст
                if not in_paragraph:
                    html_lines.append("<p>")
                    in_paragraph = True
                html_lines.append(line_stripped + " ")
        
        # Закрываем последний параграф
        if in_paragraph:
            html_lines.append("</p>")
        
        html = "".join(html_lines)
        
        # Добавляем заголовок, если его нет
        if not html.strip().startswith("<h1>") and not html.strip().startswith("<h2>"):
            html = f"<h1>{title}</h1>{html}"
        
        return html
    
    async def _update_deliverable_section(
        self,
        session: AsyncSession,
        deliverable_section: DeliverableSection,
        content_html: str,
        used_source_section_ids: List[UUID],
        changed_by_user_id: UUID
    ) -> None:
        """
        Обновляет deliverable_section и создает запись в истории.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            deliverable_section: Секция для обновления
            content_html: Сгенерированный HTML контент
            used_source_section_ids: Список ID использованных source_sections
            changed_by_user_id: UUID пользователя, инициировавшего изменение
        """
        # Обновляем deliverable_section
        deliverable_section.content_html = content_html
        deliverable_section.status = "draft_ai"
        deliverable_section.used_source_section_ids = used_source_section_ids
        
        # Создаем запись в истории (снапшот того, что сгенерировал AI)
        history_entry = DeliverableSectionHistory(
            section_id=deliverable_section.id,
            content_snapshot=content_html,
            changed_by_user_id=changed_by_user_id,
            change_reason="AI generation"
        )
        session.add(history_entry)
        
        await session.flush()


# Класс SectionWriter удален - используйте класс Writer вместо него
# SectionWriter использовал устаревшие таблицы TemplateSection и SectionMapping


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
        target_custom_section_id: UUID,
        session: AsyncSession
    ) -> GenerationResult:
        """
        Генерирует черновик раздела на основе данных из Протокола, используя Граф Шаблонов и Глобальный контекст.
        
        Алгоритм:
        1. Сбор Глобального Контекста ("Паспорт Исследования") из study_globals
        2. Обход Графа (Поиск правил) в custom_mappings или ideal_mappings
        3. Поиск Реального Контента (Retrieval) в source_sections
        4. Сборка Промпта (Prompt Engineering)
        5. Генерация и Ответ через LLM
        
        Args:
            project_id: UUID проекта
            target_custom_section_id: UUID целевой пользовательской секции (custom_section_id)
            session: SQLAlchemy асинхронная сессия
            
        Returns:
            GenerationResult с сгенерированным контентом и метаданными
            
        Raises:
            ValueError: Если не найдены правила маппинга или исходный контент
        """
        # Step 1: Сбор Глобального Контекста ("Паспорт Исследования")
        global_context_string = await self._collect_global_context(session, project_id)
        
        # Step 2: Обход Графа (Поиск правил)
        mappings = await self._find_mapping_rules(session, target_custom_section_id)
        
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
            if isinstance(mapping, CustomMapping):
                source_id = mapping.source_custom_section_id or mapping.source_ideal_section_id
                desc = f"CustomMapping from {source_id}"
            elif isinstance(mapping, IdealMapping):
                desc = f"IdealMapping from {mapping.source_ideal_section_id}"
            else:
                desc = "Unknown mapping type"
            
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
        target_custom_section_id: UUID
    ) -> List:
        """
        Находит все правила маппинга для целевой секции (custom_section).
        Использует новую архитектуру: CustomMapping и IdealMapping.
        
        Args:
            session: SQLAlchemy асинхронная сессия
            target_custom_section_id: UUID целевой пользовательской секции (custom_section_id)
            
        Returns:
            Список правил маппинга (CustomMapping или IdealMapping)
        """
        # Сначала ищем в custom_mappings
        custom_mappings_result = await session.execute(
            select(CustomMapping)
            .where(CustomMapping.target_custom_section_id == target_custom_section_id)
            .order_by(CustomMapping.order_index)
        )
        custom_mappings = custom_mappings_result.scalars().all()
        
        if custom_mappings:
            return custom_mappings
        
        # Если нет custom_mappings, ищем через ideal_section_id
        custom_section_result = await session.execute(
            select(CustomSection).where(CustomSection.id == target_custom_section_id)
        )
        custom_section = custom_section_result.scalar_one_or_none()
        
        if custom_section and custom_section.ideal_section_id:
            ideal_mappings_result = await session.execute(
                select(IdealMapping)
                .where(IdealMapping.target_ideal_section_id == custom_section.ideal_section_id)
                .order_by(IdealMapping.order_index)
            )
            return ideal_mappings_result.scalars().all()
        
        return []
    
    async def _retrieve_source_content(
        self,
        session: AsyncSession,
        project_id: UUID,
        mappings: List
    ) -> Optional[dict]:
        """
        Находит реальные тексты из документов проекта, соответствующие source из маппингов.
        
        Для каждого маппинга находит секции документов:
        - Документ должен принадлежать project_id
        - is_current_version = TRUE (только актуальные версии)
        - custom_section_id должен совпадать с source_custom_section_id или находиться через source_ideal_section_id
        
        Args:
            session: SQLAlchemy асинхронная сессия
            project_id: UUID проекта
            mappings: Список правил маппинга (CustomMapping или IdealMapping)
            
        Returns:
            Словарь с ключами:
            - "content": объединенный контент всех найденных секций
            - "headers": список заголовков
            - "section_ids": список UUID использованных секций
            Или None, если контент не найден
        """
        all_sections = []
        all_section_ids = []
        seen_section_ids = set()
        
        for mapping in mappings:
            # Определяем список custom_section_ids для поиска
            custom_section_ids_to_search = []
            
            if isinstance(mapping, CustomMapping):
                if mapping.source_custom_section_id:
                    custom_section_ids_to_search = [mapping.source_custom_section_id]
                elif mapping.source_ideal_section_id:
                    # Находим все custom_sections с таким ideal_section_id
                    custom_sections_result = await session.execute(
                        select(CustomSection).where(
                            CustomSection.ideal_section_id == mapping.source_ideal_section_id
                        )
                    )
                    custom_sections = custom_sections_result.scalars().all()
                    custom_section_ids_to_search = [cs.id for cs in custom_sections]
            elif isinstance(mapping, IdealMapping):
                # Для IdealMapping находим все custom_sections с таким ideal_section_id
                custom_sections_result = await session.execute(
                    select(CustomSection).where(
                        CustomSection.ideal_section_id == mapping.source_ideal_section_id
                    )
                )
                custom_sections = custom_sections_result.scalars().all()
                custom_section_ids_to_search = [cs.id for cs in custom_sections]
            else:
                continue
            
            if not custom_section_ids_to_search:
                continue
            
            # Находим секции документов с фильтром is_current_version = TRUE
            result = await session.execute(
                select(SourceSection, SourceDocument)
                .join(SourceDocument, SourceSection.document_id == SourceDocument.id)
                .where(
                    and_(
                        SourceDocument.project_id == project_id,
                        SourceDocument.is_current_version == True,
                        SourceSection.custom_section_id.in_(custom_section_ids_to_search)
                    )
                )
                .order_by(desc(SourceDocument.created_at))
            )
            
            rows = result.all()
            for doc_section, source_doc in rows:
                if doc_section.id in seen_section_ids:
                    continue
                seen_section_ids.add(doc_section.id)
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
        mappings: List
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

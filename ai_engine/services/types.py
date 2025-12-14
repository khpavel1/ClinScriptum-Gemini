"""
Типы данных для парсинга документов.
"""
from dataclasses import dataclass
from typing import Optional, Dict, List, Any


@dataclass
class Section:
    """
    Представляет секцию документа после парсинга.
    Соответствует структуре таблицы source_sections.
    """
    section_number: Optional[str] = None  # например "3.1.2"
    header: Optional[str] = None  # например "Критерии включения"
    content_text: Optional[str] = None  # Чистый текст для поиска
    content_markdown: Optional[str] = None  # Текст с разметкой таблиц (для LLM)
    content_structure: Optional[Dict[str, Any]] = None  # Структурированное представление таблиц (JSON)
    page_number: Optional[int] = None
    hierarchy_level: Optional[int] = None  # Уровень вложенности заголовка (1 для H1, 2 для H2 и т.д.)

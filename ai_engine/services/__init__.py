"""
Сервисы для парсинга документов.
"""
from .base_parser import BaseParser
from .docling_parser import DoclingParser
from .types import Section

__all__ = ["BaseParser", "DoclingParser", "Section"]

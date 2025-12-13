"""
Парсер документов на основе Docling.
Конвертирует PDF/DOCX в Markdown и разбивает на секции по заголовкам.
"""
import re
import asyncio
from typing import List
from pathlib import Path
from docling.document_converter import DocumentConverter
from docling.datamodel.document import ConversionResult
from .base_parser import BaseParser
from .types import Section


class DoclingParser(BaseParser):
    """
    Парсер документов с использованием Docling.
    Поддерживает PDF и DOCX файлы.
    """
    
    def __init__(self):
        """
        Инициализирует Docling конвертер.
        """
        self.converter = DocumentConverter()
    
    async def parse(self, file_path: str) -> List[Section]:
        """
        Парсит документ через Docling и разбивает на секции по заголовкам.
        
        Args:
            file_path: Путь к файлу (PDF или DOCX)
            
        Returns:
            Список секций документа
            
        Raises:
            FileNotFoundError: Если файл не найден
            ValueError: Если файл не может быть обработан
        """
        # Проверяем существование файла
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Файл не найден: {file_path}")
        
        # Конвертируем документ в Markdown через Docling
        # Оборачиваем синхронный вызов в executor, чтобы не блокировать event loop
        result: ConversionResult = await asyncio.to_thread(self.converter.convert, file_path)
        
        # Получаем Markdown контент
        markdown_content = await asyncio.to_thread(result.document.export_to_markdown)
        
        # Разбиваем на секции по заголовкам
        sections = self._split_into_sections(markdown_content)
        
        return sections
    
    def _split_into_sections(self, markdown: str) -> List[Section]:
        """
        Разбивает Markdown контент на секции по заголовкам (H1, H2, H3).
        
        Args:
            markdown: Markdown контент документа
            
        Returns:
            Список секций
        """
        sections: List[Section] = []
        lines = markdown.split('\n')
        
        current_section: Section = None
        current_content_lines: List[str] = []
        current_header: str = None
        current_section_number: str = None
        current_hierarchy_level: int = None
        
        for line in lines:
            # Проверяем, является ли строка заголовком
            header_match = re.match(r'^(#{1,6})\s+(.+)$', line)
            
            if header_match:
                # Сохраняем предыдущую секцию, если она есть
                if current_section is not None or current_content_lines:
                    content_markdown = '\n'.join(current_content_lines).strip()
                    content_text = self._markdown_to_text(content_markdown)
                    
                    section = Section(
                        section_number=current_section_number,
                        header=current_header,
                        content_text=content_text,
                        content_markdown=content_markdown if content_markdown else None,
                        hierarchy_level=current_hierarchy_level
                    )
                    sections.append(section)
                
                # Начинаем новую секцию
                level = len(header_match.group(1))
                header_text = header_match.group(2).strip()
                
                # Извлекаем номер секции из заголовка (например, "3.1 Study Design" -> "3.1")
                section_number_match = re.match(r'^(\d+(?:\.\d+)*)', header_text)
                section_number = section_number_match.group(1) if section_number_match else None
                
                current_header = header_text
                current_section_number = section_number
                current_hierarchy_level = level
                current_content_lines = []
                current_section = None
            else:
                # Добавляем строку к текущему контенту
                if line.strip() or current_content_lines:  # Сохраняем пустые строки внутри контента
                    current_content_lines.append(line)
        
        # Добавляем последнюю секцию
        if current_section is not None or current_content_lines:
            content_markdown = '\n'.join(current_content_lines).strip()
            content_text = self._markdown_to_text(content_markdown)
            
            section = Section(
                section_number=current_section_number,
                header=current_header,
                content_text=content_text,
                content_markdown=content_markdown if content_markdown else None,
                hierarchy_level=current_hierarchy_level
            )
            sections.append(section)
        
        return sections
    
    def _markdown_to_text(self, markdown: str) -> str:
        """
        Преобразует Markdown в чистый текст (удаляет разметку).
        
        Args:
            markdown: Markdown текст
            
        Returns:
            Чистый текст без разметки
        """
        if not markdown:
            return ""
        
        # Удаляем заголовки
        text = re.sub(r'^#{1,6}\s+', '', markdown, flags=re.MULTILINE)
        
        # Удаляем жирный и курсив
        text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
        text = re.sub(r'\*([^*]+)\*', r'\1', text)
        text = re.sub(r'__([^_]+)__', r'\1', text)
        text = re.sub(r'_([^_]+)_', r'\1', text)
        
        # Удаляем ссылки [текст](url) -> текст
        text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
        
        # Удаляем изображения ![alt](url)
        text = re.sub(r'!\[([^\]]*)\]\([^\)]+\)', '', text)
        
        # Удаляем код блоки
        text = re.sub(r'```[\s\S]*?```', '', text)
        text = re.sub(r'`([^`]+)`', r'\1', text)
        
        # Удаляем списки (маркеры)
        text = re.sub(r'^\s*[-*+]\s+', '', text, flags=re.MULTILINE)
        text = re.sub(r'^\s*\d+\.\s+', '', text, flags=re.MULTILINE)
        
        # Удаляем горизонтальные линии
        text = re.sub(r'^---+$', '', text, flags=re.MULTILINE)
        
        # Очищаем множественные пробелы и переносы строк
        text = re.sub(r'\n\s*\n\s*\n+', '\n\n', text)
        text = re.sub(r' +', ' ', text)
        
        return text.strip()

"""
Парсер документов на основе Docling.
Конвертирует PDF/DOCX в Markdown и разбивает на секции по заголовкам.
"""
import re
import asyncio
import json
from typing import List, Dict, Any, Optional
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
        Извлекает таблицы и сохраняет их в структурированном JSON формате.
        
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
        
        # Извлекаем таблицы из документа
        tables_data = await self._extract_tables(result)
        
        # Разбиваем на секции по заголовкам
        sections = self._split_into_sections(markdown_content, tables_data)
        
        return sections
    
    async def _extract_tables(self, result: ConversionResult) -> Dict[int, List[Dict[str, Any]]]:
        """
        Извлекает таблицы из документа Docling и преобразует их в структурированный JSON.
        
        Args:
            result: Результат конвертации Docling
            
        Returns:
            Словарь, где ключ - номер страницы, значение - список таблиц в структурированном формате
        """
        tables_by_page: Dict[int, List[Dict[str, Any]]] = {}
        
        # Оборачиваем синхронный доступ к таблицам в executor
        def _extract_sync():
            tables_list = []
            for table in result.document.tables:
                try:
                    # Пытаемся использовать pandas DataFrame, если доступен
                    try:
                        import pandas as pd
                        # Экспортируем таблицу в DataFrame (doc опционален, но может помочь с контекстом)
                        df = table.export_to_dataframe(doc=result.document) if hasattr(table, 'export_to_dataframe') else None
                        
                        if df is None:
                            # Если export_to_dataframe не доступен, пропускаем таблицу
                            continue
                        
                        # Преобразуем DataFrame в структурированный JSON
                        # Формат: список списков (первая строка - заголовки, остальные - данные)
                        headers = df.columns.tolist() if len(df.columns) > 0 else []
                        rows = []
                        has_merged_cells = False
                        
                        # Преобразуем каждую строку, обрабатывая NaN значения
                        for idx, row in df.iterrows():
                            row_data = []
                            for val in row:
                                if pd.isna(val):
                                    row_data.append("")
                                    has_merged_cells = True
                                else:
                                    # Преобразуем значение в строку, сохраняя None как пустую строку
                                    row_data.append(str(val) if val is not None else "")
                            rows.append(row_data)
                        
                        table_data = {
                            "type": "table",
                            "headers": headers,
                            "rows": rows,
                            "row_count": len(df),
                            "column_count": len(df.columns) if len(df.columns) > 0 else 0,
                            "has_merged_cells": has_merged_cells
                        }
                    except ImportError:
                        # Если pandas недоступен, используем альтернативный подход
                        # Пытаемся получить данные таблицы напрямую
                        # Docling может предоставить доступ к ячейкам таблицы
                        if hasattr(table, 'cells') or hasattr(table, 'rows'):
                            # Простой подход: пытаемся получить структуру таблицы
                            # Это зависит от внутренней структуры Docling Table
                            table_data = {
                                "type": "table",
                                "headers": [],
                                "rows": [],
                                "row_count": 0,
                                "column_count": 0,
                                "has_merged_cells": False,
                                "note": "Table structure extracted without pandas - may need manual processing"
                            }
                        else:
                            # Если нет доступа к структуре, пропускаем таблицу
                            continue
                    
                    # Получаем номер страницы таблицы, если доступен
                    page_num = None
                    if hasattr(table, 'prov') and table.prov:
                        # Пытаемся извлечь номер страницы из provenance
                        for prov_item in table.prov:
                            if hasattr(prov_item, 'page') and prov_item.page is not None:
                                page_num = prov_item.page
                                break
                            # Альтернативный способ: проверяем, есть ли атрибут page_num
                            if hasattr(prov_item, 'page_num') and prov_item.page_num is not None:
                                page_num = prov_item.page_num
                                break
                    
                    table_data["page_number"] = page_num
                    tables_list.append(table_data)
                except Exception as e:
                    # Логируем ошибку, но продолжаем обработку других таблиц
                    print(f"Ошибка при извлечении таблицы: {str(e)}")
                    continue
            
            return tables_list
        
        tables_list = await asyncio.to_thread(_extract_sync)
        
        # Группируем таблицы по страницам
        for table_data in tables_list:
            page_num = table_data.get("page_number")
            if page_num is not None:
                if page_num not in tables_by_page:
                    tables_by_page[page_num] = []
                tables_by_page[page_num].append(table_data)
            else:
                # Если номер страницы неизвестен, добавляем в страницу 0
                if 0 not in tables_by_page:
                    tables_by_page[0] = []
                tables_by_page[0].append(table_data)
        
        return tables_by_page
    
    def _split_into_sections(self, markdown: str, tables_data: Dict[int, List[Dict[str, Any]]]) -> List[Section]:
        """
        Разбивает Markdown контент на секции по заголовкам (H1, H2, H3).
        Привязывает таблицы к соответствующим секциям по номеру страницы.
        
        Args:
            markdown: Markdown контент документа
            tables_data: Словарь таблиц, сгруппированных по страницам
            
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
        current_page_number: Optional[int] = None
        
        for line in lines:
            # Проверяем, является ли строка заголовком
            header_match = re.match(r'^(#{1,6})\s+(.+)$', line)
            
            if header_match:
                # Сохраняем предыдущую секцию, если она есть
                if current_section is not None or current_content_lines:
                    content_markdown = '\n'.join(current_content_lines).strip()
                    content_text = self._markdown_to_text(content_markdown)
                    
                    # Ищем таблицы для текущей секции по номеру страницы
                    content_structure = None
                    if current_page_number is not None and current_page_number in tables_data:
                        tables_in_section = tables_data[current_page_number]
                        if tables_in_section:
                            content_structure = {
                                "tables": tables_in_section,
                                "table_count": len(tables_in_section)
                            }
                    
                    section = Section(
                        section_number=current_section_number,
                        header=current_header,
                        content_text=content_text,
                        content_markdown=content_markdown if content_markdown else None,
                        content_structure=content_structure,
                        page_number=current_page_number,
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
                # Сбрасываем номер страницы для новой секции (будет обновлен при обнаружении)
                current_page_number = None
            else:
                # Пытаемся извлечь номер страницы из специальных маркеров (если есть)
                # Это зависит от формата Markdown, который генерирует Docling
                page_match = re.search(r'\[Page\s+(\d+)\]', line, re.IGNORECASE)
                if page_match:
                    current_page_number = int(page_match.group(1))
                
                # Добавляем строку к текущему контенту
                if line.strip() or current_content_lines:  # Сохраняем пустые строки внутри контента
                    current_content_lines.append(line)
        
        # Добавляем последнюю секцию
        if current_section is not None or current_content_lines:
            content_markdown = '\n'.join(current_content_lines).strip()
            content_text = self._markdown_to_text(content_markdown)
            
            # Ищем таблицы для последней секции
            content_structure = None
            if current_page_number is not None and current_page_number in tables_data:
                tables_in_section = tables_data[current_page_number]
                if tables_in_section:
                    content_structure = {
                        "tables": tables_in_section,
                        "table_count": len(tables_in_section)
                    }
            
            section = Section(
                section_number=current_section_number,
                header=current_header,
                content_text=content_text,
                content_markdown=content_markdown if content_markdown else None,
                content_structure=content_structure,
                page_number=current_page_number,
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

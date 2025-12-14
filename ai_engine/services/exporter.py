"""
Сервис для экспорта готовых документов (deliverables) в различные форматы.
Использует Pandoc для высококачественной конвертации HTML в DOCX.
"""
import tempfile
import os
from pathlib import Path
from typing import Optional
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import pypandoc

from models import DeliverableSection, Deliverable


async def export_deliverable_to_docx(
    deliverable_id: UUID,
    db: AsyncSession,
    reference_docx: Optional[str] = None
) -> bytes:
    """
    Экспортирует deliverable в формат DOCX используя Pandoc.
    
    Процесс:
    1. Получает все DeliverableSections для документа, отсортированные по order_index
    2. Объединяет их content_html в один большой HTML документ
    3. Конвертирует HTML в DOCX используя pypandoc.convert_text
    4. Опционально применяет корпоративный шаблон (reference.docx)
    5. Возвращает бинарные данные DOCX файла
    
    Args:
        deliverable_id: UUID документа для экспорта
        db: SQLAlchemy асинхронная сессия
        reference_docx: Опциональный путь к шаблону DOCX с корпоративными стилями
        
    Returns:
        Бинарные данные DOCX файла
        
    Raises:
        ValueError: Если deliverable не найден или нет секций для экспорта
        RuntimeError: Если произошла ошибка при конвертации через Pandoc
    """
    # Step 1: Проверяем существование deliverable
    deliverable_result = await db.execute(
        select(Deliverable).where(Deliverable.id == deliverable_id)
    )
    deliverable = deliverable_result.scalar_one_or_none()
    
    if not deliverable:
        raise ValueError(f"Deliverable not found: {deliverable_id}")
    
    # Step 2: Получаем все секции, отсортированные по order_index
    sections_result = await db.execute(
        select(DeliverableSection)
        .where(DeliverableSection.deliverable_id == deliverable_id)
        .order_by(DeliverableSection.order_index)
    )
    sections = sections_result.scalars().all()
    
    if not sections:
        raise ValueError(f"No sections found for deliverable: {deliverable_id}")
    
    # Step 3: Объединяем content_html всех секций
    html_parts = []
    
    # Добавляем базовую HTML структуру
    html_parts.append("<!DOCTYPE html>")
    html_parts.append("<html><head><meta charset='UTF-8'></head><body>")
    
    # Добавляем заголовок документа
    html_parts.append(f"<h1>{deliverable.title}</h1>")
    
    # Объединяем контент секций
    for section in sections:
        if section.content_html:
            # Обертываем каждую секцию в div для лучшей структуры
            html_parts.append(f"<div class='section'>")
            html_parts.append(section.content_html)
            html_parts.append("</div>")
    
    html_parts.append("</body></html>")
    
    combined_html = "\n".join(html_parts)
    
    # Step 4: Конвертируем HTML в DOCX используя Pandoc
    temp_file_path = None
    try:
        # Подготавливаем extra_args для Pandoc
        extra_args = []
        
        # Добавляем reference.docx если указан
        if reference_docx and os.path.exists(reference_docx):
            extra_args.append(f"--reference-doc={reference_docx}")
        
        # Дополнительные параметры для лучшего качества конвертации
        extra_args.extend([
            "--standalone",
            "--wrap=none",  # Не переносим строки автоматически
        ])
        
        # Конвертируем HTML в DOCX
        # pypandoc.convert_text может вернуть bytes или путь к временному файлу
        result = pypandoc.convert_text(
            combined_html,
            "docx",
            format="html",
            extra_args=extra_args,
            encoding="utf-8"
        )
        
        # Обрабатываем результат в зависимости от типа
        if isinstance(result, bytes):
            # Если вернулись bytes напрямую - возвращаем их
            return result
        elif isinstance(result, str):
            # Если вернулась строка, это может быть путь к временному файлу
            if os.path.exists(result):
                # Читаем файл и удаляем его после чтения
                try:
                    with open(result, "rb") as f:
                        docx_bytes = f.read()
                    # Удаляем временный файл
                    try:
                        os.remove(result)
                    except OSError:
                        pass  # Игнорируем ошибки удаления
                    return docx_bytes
                except Exception as e:
                    raise RuntimeError(f"Error reading temporary DOCX file: {str(e)}")
            else:
                # Если это не путь к файлу, пытаемся закодировать как UTF-8
                # (хотя это маловероятно для DOCX)
                return result.encode("utf-8")
        else:
            raise RuntimeError(f"Unexpected return type from pypandoc: {type(result)}")
            
    except RuntimeError:
        # Пробрасываем RuntimeError дальше
        raise
    except Exception as e:
        raise RuntimeError(f"Error converting HTML to DOCX with Pandoc: {str(e)}")
    finally:
        # Очищаем временный файл, если он был создан
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                pass  # Игнорируем ошибки удаления


async def export_deliverable_to_docx_file(
    deliverable_id: UUID,
    db: AsyncSession,
    output_path: str,
    reference_docx: Optional[str] = None
) -> str:
    """
    Экспортирует deliverable в DOCX файл на диске.
    
    Args:
        deliverable_id: UUID документа для экспорта
        db: SQLAlchemy асинхронная сессия
        output_path: Путь для сохранения DOCX файла
        reference_docx: Опциональный путь к шаблону DOCX с корпоративными стилями
        
    Returns:
        Путь к созданному файлу
        
    Raises:
        ValueError: Если deliverable не найден или нет секций для экспорта
        RuntimeError: Если произошла ошибка при конвертации или записи файла
    """
    # Получаем бинарные данные
    docx_bytes = await export_deliverable_to_docx(
        deliverable_id=deliverable_id,
        db=db,
        reference_docx=reference_docx
    )
    
    # Сохраняем в файл
    try:
        with open(output_path, "wb") as f:
            f.write(docx_bytes)
        return output_path
    except Exception as e:
        raise RuntimeError(f"Error writing DOCX file to {output_path}: {str(e)}")

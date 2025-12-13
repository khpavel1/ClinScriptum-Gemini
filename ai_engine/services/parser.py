"""
Сервис для обработки документов: скачивание, парсинг и сохранение в БД.
"""
import asyncio
import tempfile
import uuid
from pathlib import Path
from typing import List, Optional
import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import AsyncSessionLocal
from models import DocumentSection
from services import DoclingParser, Section


async def download_file_from_url(url: str, output_path: Path) -> None:
    """
    Скачивает файл по URL.
    
    Args:
        url: URL файла для скачивания
        output_path: Путь для сохранения файла
        
    Raises:
        httpx.HTTPError: Если произошла ошибка при скачивании
    """
    async with httpx.AsyncClient(timeout=300.0) as client:
        async with client.stream("GET", url) as response:
            response.raise_for_status()
            with open(output_path, "wb") as f:
                async for chunk in response.aiter_bytes():
                    f.write(chunk)


async def download_file_from_supabase_storage(
    file_path: str,
    output_path: Path,
    bucket_name: Optional[str] = None
) -> None:
    """
    Скачивает файл из Supabase Storage.
    
    Args:
        file_path: Путь к файлу в бакете Supabase Storage
        output_path: Путь для сохранения файла
        bucket_name: Имя бакета (по умолчанию из настроек)
        
    Raises:
        ValueError: Если не настроены Supabase credentials
        Exception: Если произошла ошибка при скачивании
    """
    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        raise ValueError("Supabase credentials not configured")
    
    from supabase import create_client, Client
    
    def _download():
        """Синхронная функция для скачивания файла."""
        supabase: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
        bucket = bucket_name or settings.SUPABASE_STORAGE_BUCKET
        
        # Скачиваем файл из Storage
        data = supabase.storage.from_(bucket).download(file_path)
        return data
    
    # Выполняем синхронную операцию в отдельном потоке
    data = await asyncio.to_thread(_download)
    
    # Сохраняем в файл
    with open(output_path, "wb") as f:
        f.write(data)


async def process_document(
    doc_id: str,
    file_url: Optional[str] = None,
    file_path: Optional[str] = None,
    session: Optional[AsyncSession] = None
) -> List[dict]:
    """
    Обрабатывает документ: скачивает, парсит и сохраняет секции в БД.
    
    Args:
        doc_id: UUID документа в таблице source_documents
        file_url: URL файла для скачивания (если файл доступен по URL)
        file_path: Путь к файлу в Supabase Storage (если файл в Storage)
        session: SQLAlchemy сессия (если не указана, создается новая)
        
    Returns:
        Список словарей с секциями: [{header: str, content: str, page: int}]
        
    Raises:
        ValueError: Если не указан file_url или file_path
        FileNotFoundError: Если файл не найден
        Exception: Если произошла ошибка при обработке
    """
    if not file_url and not file_path:
        raise ValueError("Either file_url or file_path must be provided")
    
    # Создаем временный файл для скачивания
    temp_dir = Path(tempfile.gettempdir())
    temp_file = temp_dir / f"doc_{uuid.uuid4().hex}.tmp"
    
    try:
        # Скачиваем файл
        if file_url:
            # Если это URL, скачиваем напрямую
            if file_url.startswith("http://") or file_url.startswith("https://"):
                await download_file_from_url(file_url, temp_file)
            else:
                # Иначе считаем, что это путь в Supabase Storage
                await download_file_from_supabase_storage(file_url, temp_file)
        elif file_path:
            # Путь в Supabase Storage
            await download_file_from_supabase_storage(file_path, temp_file)
        
        # Парсим документ через DoclingParser
        parser = DoclingParser()
        sections: List[Section] = await parser.parse(str(temp_file))
        
        # Преобразуем секции в формат для возврата
        result_sections = []
        for section in sections:
            result_sections.append({
                "header": section.header,
                "content": section.content_markdown or section.content_text or "",
                "page": section.page_number
            })
        
        # Сохраняем секции в БД
        # Используем переданную сессию или создаем новую
        if session:
            await _save_sections_to_db(session, doc_id, sections)
        else:
            async with AsyncSessionLocal() as db_session:
                await _save_sections_to_db(db_session, doc_id, sections)
                await db_session.commit()
        
        return result_sections
        
    finally:
        # Удаляем временный файл
        if temp_file.exists():
            temp_file.unlink()


async def _save_sections_to_db(
    session: AsyncSession,
    document_id: str,
    sections: List[Section]
) -> None:
    """
    Сохраняет секции документа в таблицу document_sections.
    
    Args:
        session: SQLAlchemy асинхронная сессия
        document_id: UUID документа
        sections: Список секций для сохранения
    """
    # Преобразуем document_id в UUID, если это строка
    doc_uuid = uuid.UUID(document_id) if isinstance(document_id, str) else document_id
    
    # Создаем записи для каждой секции
    for section in sections:
        db_section = DocumentSection(
            document_id=doc_uuid,
            section_number=section.section_number,
            header=section.header,
            page_number=section.page_number,
            content_text=section.content_text,
            content_markdown=section.content_markdown,
        )
        session.add(db_section)
    
    # Коммитим изменения
    await session.flush()

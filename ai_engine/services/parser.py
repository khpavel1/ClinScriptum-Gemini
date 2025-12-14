"""
Сервис для обработки документов: скачивание, парсинг и сохранение в БД.
Интегрирован с классификатором секций для привязки к шаблонам.
"""
import asyncio
import tempfile
import uuid
import time
from pathlib import Path
from typing import List, Optional
from datetime import datetime
import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from config import settings
from database import AsyncSessionLocal
from models import SourceSection, SourceDocument
from services import DoclingParser, Section
from services.llm import LLMClient
from services.classifier import SectionClassifier


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
    template_id: Optional[str] = None,
    session: Optional[AsyncSession] = None
) -> List[dict]:
    """
    Обрабатывает документ: скачивает, парсит, классифицирует секции и сохраняет в БД.
    
    Args:
        doc_id: UUID документа в таблице source_documents
        file_url: URL файла для скачивания (если файл доступен по URL)
        file_path: Путь к файлу в Supabase Storage (если файл в Storage)
        template_id: UUID шаблона документа для классификации секций
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
    
    start_time = time.time()
    temp_dir = Path(tempfile.gettempdir())
    temp_file = temp_dir / f"doc_{uuid.uuid4().hex}.tmp"
    
    # Инициализируем сервисы
    llm_client = LLMClient()
    classifier = SectionClassifier(llm_client)
    
    # Используем переданную сессию или создаем новую
    use_external_session = session is not None
    if not session:
        session = AsyncSessionLocal()
    
    try:
        # Скачиваем файл
        if file_url:
            if file_url.startswith("http://") or file_url.startswith("https://"):
                await download_file_from_url(file_url, temp_file)
            else:
                await download_file_from_supabase_storage(file_url, temp_file)
        elif file_path:
            await download_file_from_supabase_storage(file_path, temp_file)
        
        # Парсим документ через DoclingParser
        parser = DoclingParser()
        sections: List[Section] = await parser.parse(str(temp_file))
        
        # Обновляем статус документа на "processing"
        doc_uuid = uuid.UUID(doc_id) if isinstance(doc_id, str) else doc_id
        doc_result = await session.execute(
            select(SourceDocument).where(SourceDocument.id == doc_uuid)
        )
        source_doc = doc_result.scalar_one_or_none()
        if source_doc:
            source_doc.status = "processing"
        
        # Классифицируем и сохраняем секции
        template_uuid = None
        if template_id:
            template_uuid = uuid.UUID(template_id) if isinstance(template_id, str) else template_id
        
        result_sections = []
        for section in sections:
            # Классифицируем секцию, если указан template_id (custom_template_id)
            # custom_section_id теперь ссылается на custom_section_id
            custom_section_id = None
            if template_uuid and section.header:
                custom_section_id = await classifier.classify_section(
                    session, section.header, template_uuid
                )
            
            result_sections.append({
                "header": section.header,
                "content": section.content_markdown or section.content_text or "",
                "page": section.page_number,
                "custom_section_id": str(custom_section_id) if custom_section_id else None
            })
        
        # Сохраняем секции в БД
        await _save_sections_to_db(
            session, doc_id, sections, template_uuid, classifier, llm_client
        )
        
        # Собираем метрики парсинга
        parsing_time = time.time() - start_time
        page_count = max((s.page_number or 0 for s in sections), default=0)
        
        # Обновляем метаданные документа
        if source_doc:
            source_doc.parsing_metadata = {
                "parsing_time_seconds": parsing_time,
                "page_count": page_count,
                "sections_count": len(sections),
                "parsed_at": datetime.utcnow().isoformat()
            }
            source_doc.status = "indexed"
        
        if not use_external_session:
            await session.commit()
        
        return result_sections
        
    except Exception as e:
        # Обновляем статус на "error" при ошибке
        if session:
            try:
                doc_uuid = uuid.UUID(doc_id) if isinstance(doc_id, str) else doc_id
                doc_result = await session.execute(
                    select(SourceDocument).where(SourceDocument.id == doc_uuid)
                )
                source_doc = doc_result.scalar_one_or_none()
                if source_doc:
                    source_doc.status = "error"
                    source_doc.parsing_metadata = {
                        "error": str(e),
                        "parsed_at": datetime.utcnow().isoformat()
                    }
                if not use_external_session:
                    await session.commit()
            except:
                pass
        raise
    finally:
        # Удаляем временный файл
        if temp_file.exists():
            temp_file.unlink()
        # Закрываем сессию только если мы её создали
        if not use_external_session and session:
            await session.close()


async def _save_sections_to_db(
    session: AsyncSession,
    document_id: str,
    sections: List[Section],
    template_id: Optional[uuid.UUID] = None,
    classifier: Optional[SectionClassifier] = None,
    llm_client: Optional[LLMClient] = None
) -> None:
    """
    Сохраняет секции документа в таблицу source_sections.
    Классифицирует секции и создает эмбеддинги.
    
    Args:
        session: SQLAlchemy асинхронная сессия
        document_id: UUID документа
        sections: Список секций для сохранения
        template_id: UUID шаблона для классификации
        classifier: Классификатор секций (опционально)
        llm_client: Клиент для создания эмбеддингов (опционально)
    """
    # Преобразуем document_id в UUID, если это строка
    doc_uuid = uuid.UUID(document_id) if isinstance(document_id, str) else document_id
    
    # Создаем записи для каждой секции
    for section in sections:
        # Классифицируем секцию, если указан template_id и classifier
        custom_section_id = None
        if template_id and classifier and section.header:
            custom_section_id = await classifier.classify_section(
                session, section.header, template_id
            )
        
        # Создаем эмбеддинг для секции (для гибридного поиска)
        embedding = None
        if llm_client:
            # Используем заголовок + начало контента для эмбеддинга
            text_for_embedding = section.header or ""
            if section.content_text:
                # Берем первые 500 символов контента
                text_for_embedding += " " + section.content_text[:500]
            
            if text_for_embedding.strip():
                try:
                    embedding = await llm_client.get_embedding(text_for_embedding.strip())
                except Exception as e:
                    print(f"Ошибка при создании эмбеддинга для секции: {str(e)}")
        
        db_section = SourceSection(
            document_id=doc_uuid,
            custom_section_id=custom_section_id,
            section_number=section.section_number,
            header=section.header,
            page_number=section.page_number,
            content_text=section.content_text,
            content_markdown=section.content_markdown,
            embedding=embedding
        )
        session.add(db_section)
    
    # Коммитим изменения
    await session.flush()

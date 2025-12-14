"""
Celery tasks for document processing.
Handles async database operations within synchronous Celery workers.
"""
from typing import List, Optional
from asgiref.sync import async_to_sync

from celery_app import celery_app
from database import AsyncSessionLocal
from services.parser import process_document


@celery_app.task(
    bind=True,
    name="ai_engine.process_document",
    max_retries=3,
    default_retry_delay=60,  # Retry after 60 seconds
)
def process_document_task(
    self,
    doc_id: str,
    file_url: Optional[str] = None,
    file_path: Optional[str] = None,
    template_id: Optional[str] = None
) -> List[dict]:
    """
    Celery task for processing documents.
    Downloads, parses, classifies sections, and saves to database.
    
    Args:
        doc_id: UUID документа в таблице source_documents
        file_url: URL файла для скачивания (если файл доступен по URL)
        file_path: Путь к файлу в Supabase Storage (если файл в Storage)
        template_id: UUID шаблона документа для классификации секций
        
    Returns:
        Список словарей с секциями: [{header: str, content: str, page: int}]
        
    Raises:
        Exception: Если произошла ошибка при обработке (будет повторена попытка)
    """
    async def _process():
        """Async wrapper for process_document."""
        # Create a new async session for this task
        async with AsyncSessionLocal() as session:
            try:
                # Call the original async process_document function
                result = await process_document(
                    doc_id=doc_id,
                    file_url=file_url,
                    file_path=file_path,
                    template_id=template_id,
                    session=session
                )
                return result
            except Exception as e:
                # Log error and re-raise for Celery retry mechanism
                print(f"Error processing document {doc_id}: {str(e)}")
                raise
    
    # Execute async function in sync context using async_to_sync
    # This creates a new event loop if needed and runs the async function
    try:
        return async_to_sync(_process)()
    except Exception as exc:
        # Retry task on failure
        raise self.retry(exc=exc)

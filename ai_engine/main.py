"""
Точка входа для микросервиса AI Engine на FastAPI.
Включает настройку CORS, эндпоинты и запуск Uvicorn.
"""
from fastapi import FastAPI, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from contextlib import asynccontextmanager
import uvicorn
import io
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import init_db, close_db, get_db
from models import IdealTemplate, CustomTemplate, DeliverableSection, Deliverable
from services import DoclingParser, Section
from tasks import process_document_task
from services.llm import LLMClient
from services.extractor import GlobalExtractor
from services.writer import Writer
from services.exporter import export_deliverable_to_docx
from sqlalchemy import select


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Управление жизненным циклом приложения.
    Инициализация и закрытие соединений с БД.
    """
    # Инициализация при запуске
    await init_db()
    yield
    # Очистка при остановке
    await close_db()


# Создаем экземпляр FastAPI приложения
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)

# Настройка CORS
# Разрешаем запросы с фронтенда (Next.js)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],  # Next.js по умолчанию на порту 3000
    allow_credentials=True,
    allow_methods=["*"],  # Разрешаем все HTTP методы
    allow_headers=["*"],  # Разрешаем все заголовки
)

# Инициализация парсера
# Можно легко заменить на AzureParser или другой парсер
parser = DoclingParser()


@app.get("/health")
async def health_check():
    """
    Простой эндпоинт для проверки работы сервиса.
    """
    return {
        "status": "ok",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }


# Модели для API
class ParseRequest(BaseModel):
    """Запрос на парсинг документа."""
    file_path: str


class SectionResponse(BaseModel):
    """Ответ с секцией документа."""
    section_number: Optional[str] = None
    header: Optional[str] = None
    content_text: Optional[str] = None
    content_markdown: Optional[str] = None
    page_number: Optional[int] = None
    hierarchy_level: Optional[int] = None
    
    @classmethod
    def from_section(cls, section: Section) -> "SectionResponse":
        """Создает ответ из объекта Section."""
        return cls(
            section_number=section.section_number,
            header=section.header,
            content_text=section.content_text,
            content_markdown=section.content_markdown,
            page_number=section.page_number,
            hierarchy_level=section.hierarchy_level,
        )


class ParseResponse(BaseModel):
    """Ответ на запрос парсинга."""
    sections: List[SectionResponse]
    total_sections: int


@app.post("/parse", response_model=ParseResponse)
async def parse_document(request: ParseRequest):
    """
    Парсит документ и возвращает список секций.
    
    Args:
        request: Запрос с путем к файлу
        
    Returns:
        Список секций документа
        
    Raises:
        HTTPException: Если файл не найден или произошла ошибка парсинга
    """
    try:
        # Парсим документ
        sections = await parser.parse(request.file_path)
        
        # Преобразуем в формат ответа
        section_responses = [SectionResponse.from_section(section) for section in sections]
        
        return ParseResponse(
            sections=section_responses,
            total_sections=len(section_responses)
        )
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при парсинге документа: {str(e)}")


# Модели для нового API эндпоинта
class ParseDocumentRequest(BaseModel):
    """Запрос на парсинг документа с сохранением в БД."""
    document_id: str
    file_path: str
    file_url: Optional[str] = None
    template_id: Optional[str] = None  # UUID шаблона для классификации секций


class ParseDocumentResponse(BaseModel):
    """Ответ на запрос парсинга документа."""
    message: str
    document_id: str
    status: str = "processing"


class GenerateRequest(BaseModel):
    """Запрос на генерацию секции документа."""
    project_id: str
    target_section_id: str  # UUID целевой секции шаблона
    deliverable_id: str  # UUID документа (deliverable), в который сохраняется секция


class GenerateResponse(BaseModel):
    """Ответ на запрос генерации секции."""
    content: str  # Markdown текст секции
    target_section_id: str


class TemplateResponse(BaseModel):
    """Ответ с информацией о шаблоне."""
    id: str
    name: str
    description: Optional[str] = None
    sections: List[dict] = []


@app.post("/api/v1/parse", response_model=ParseDocumentResponse)
async def parse_document_background(
    request: ParseDocumentRequest
):
    """
    Запускает парсинг документа через Celery и сохраняет секции в БД.
    
    Args:
        request: Запрос с document_id, file_path (или file_url) и template_id
        
    Returns:
        Ответ с подтверждением начала обработки
        
    Raises:
        HTTPException: Если произошла ошибка при запуске задачи
    """
    try:
        # Запускаем Celery задачу
        task = process_document_task.delay(
            doc_id=request.document_id,
            file_url=request.file_url,
            file_path=request.file_path,
            template_id=request.template_id
        )
        
        return ParseDocumentResponse(
            message=f"Парсинг документа запущен в очереди (task_id: {task.id})",
            document_id=request.document_id,
            status="processing"
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при запуске парсинга документа: {str(e)}"
        )


@app.post("/parse", response_model=ParseDocumentResponse)
async def parse_document(
    request: ParseDocumentRequest
):
    """
    Запускает парсинг документа через Celery (алиас для /api/v1/parse).
    """
    return await parse_document_background(request)


@app.post("/generate", response_model=GenerateResponse)
async def generate_section(
    request: GenerateRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Генерирует целевую секцию документа на основе Template Graph.
    
    Args:
        request: Запрос с project_id и target_section_id
        db: SQLAlchemy асинхронная сессия
        
    Returns:
        Сгенерированный текст секции в формате Markdown
        
    Raises:
        HTTPException: Если произошла ошибка при генерации
    """
    try:
        project_uuid = UUID(request.project_id)
        target_section_uuid = UUID(request.target_section_id)
        deliverable_uuid = UUID(request.deliverable_id)
        
        # Инициализируем сервисы
        llm_client = LLMClient()
        writer = Writer(llm_client)
        
        # Получаем deliverable_section для генерации
        from models import DeliverableSection
        deliverable_section_result = await db.execute(
            select(DeliverableSection).where(
                DeliverableSection.deliverable_id == deliverable_uuid,
                DeliverableSection.id == target_section_uuid
            )
        )
        deliverable_section = deliverable_section_result.scalar_one_or_none()
        
        if not deliverable_section:
            raise HTTPException(status_code=404, detail="Deliverable section not found")
        
        # Генерируем секцию используя новый метод
        content = await writer.generate_section(
            session=db,
            deliverable_section_id=target_section_uuid,
            changed_by_user_id=project_uuid  # TODO: получить реальный user_id из запроса
        )
        
        return GenerateResponse(
            content=content,
            target_section_id=request.target_section_id
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при генерации секции: {str(e)}"
        )


@app.get("/api/v1/export/{deliverable_id}")
async def export_deliverable(
    deliverable_id: UUID,
    reference_docx: Optional[str] = Query(None, description="Путь к шаблону DOCX с корпоративными стилями"),
    db: AsyncSession = Depends(get_db)
):
    """
    Экспортирует deliverable в формат DOCX используя Pandoc.
    
    Args:
        deliverable_id: UUID документа для экспорта
        reference_docx: Опциональный путь к шаблону DOCX с корпоративными стилями
        db: SQLAlchemy асинхронная сессия
        
    Returns:
        StreamingResponse с DOCX файлом
        
    Raises:
        HTTPException: Если deliverable не найден, нет секций или произошла ошибка конвертации
    """
    try:
        # Получаем deliverable для имени файла
        deliverable_result = await db.execute(
            select(Deliverable).where(Deliverable.id == deliverable_id)
        )
        deliverable = deliverable_result.scalar_one_or_none()
        
        if not deliverable:
            raise HTTPException(status_code=404, detail=f"Deliverable not found: {deliverable_id}")
        
        # Экспортируем в DOCX
        docx_bytes = await export_deliverable_to_docx(
            deliverable_id=deliverable_id,
            db=db,
            reference_docx=reference_docx
        )
        
        # Формируем имя файла
        filename = f"{deliverable.title or 'document'}.docx"
        # Очищаем имя файла от недопустимых символов
        filename = "".join(c for c in filename if c.isalnum() or c in (' ', '-', '_', '.')).strip()
        if not filename.endswith('.docx'):
            filename += '.docx'
        
        # Возвращаем файл как поток
        return StreamingResponse(
            io.BytesIO(docx_bytes),
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"'
            }
        )
        
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при экспорте: {str(e)}")
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Неожиданная ошибка при экспорте документа: {str(e)}"
        )


# Эндпоинт /templates удален - используйте ideal_templates или custom_templates напрямую
# Для получения списка шаблонов используйте соответствующие таблицы через Supabase клиент


if __name__ == "__main__":
    # Запуск сервера через Uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,  # Автоперезагрузка в режиме отладки
    )

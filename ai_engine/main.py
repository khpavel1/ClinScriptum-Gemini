"""
Точка входа для микросервиса AI Engine на FastAPI.
Включает настройку CORS, эндпоинты и запуск Uvicorn.
"""
from fastapi import FastAPI, HTTPException, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from contextlib import asynccontextmanager
import uvicorn
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import init_db, close_db, get_db
from models import DocTemplate, TemplateSection
from services import DoclingParser, Section
from services.parser import process_document
from services.llm import LLMClient
from services.extractor import GlobalExtractor
from services.writer import SectionWriter
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
    request: ParseDocumentRequest,
    background_tasks: BackgroundTasks
):
    """
    Запускает парсинг документа в фоне и сохраняет секции в БД.
    
    Args:
        request: Запрос с document_id, file_path (или file_url) и template_id
        background_tasks: FastAPI BackgroundTasks для асинхронной обработки
        
    Returns:
        Ответ с подтверждением начала обработки
        
    Raises:
        HTTPException: Если произошла ошибка при запуске задачи
    """
    try:
        # Добавляем задачу в фон
        background_tasks.add_task(
            process_document,
            doc_id=request.document_id,
            file_url=request.file_url,
            file_path=request.file_path,
            template_id=request.template_id
        )
        
        return ParseDocumentResponse(
            message="Парсинг документа запущен в фоне",
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
    request: ParseDocumentRequest,
    background_tasks: BackgroundTasks
):
    """
    Запускает парсинг документа в фоне (алиас для /api/v1/parse).
    """
    return await parse_document_background(request, background_tasks)


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
        writer = SectionWriter(llm_client)
        
        # Генерируем секцию
        content = await writer.generate_target_section(
            session=db,
            project_id=project_uuid,
            target_template_section_id=target_section_uuid,
            deliverable_id=deliverable_uuid
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


@app.get("/templates", response_model=List[TemplateResponse])
async def get_templates(db: AsyncSession = Depends(get_db)):
    """
    Возвращает список доступных шаблонов документов.
    
    Args:
        db: SQLAlchemy асинхронная сессия
        
    Returns:
        Список шаблонов с их секциями
    """
    try:
        # Получаем все шаблоны
        result = await db.execute(select(DocTemplate))
        templates = result.scalars().all()
        
        templates_response = []
        for template in templates:
            # Получаем секции шаблона
            sections_result = await db.execute(
                select(TemplateSection).where(TemplateSection.template_id == template.id)
            )
            sections = sections_result.scalars().all()
            
            templates_response.append(TemplateResponse(
                id=str(template.id),
                name=template.name,
                description=template.description,
                sections=[
                    {
                        "id": str(section.id),
                        "title": section.title,
                        "section_number": section.section_number,
                        "is_mandatory": section.is_mandatory
                    }
                    for section in sections
                ]
            ))
        
        return templates_response
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при получении шаблонов: {str(e)}"
        )


if __name__ == "__main__":
    # Запуск сервера через Uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,  # Автоперезагрузка в режиме отладки
    )

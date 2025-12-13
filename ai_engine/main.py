"""
Точка входа для микросервиса AI Engine на FastAPI.
Включает настройку CORS, эндпоинты и запуск Uvicorn.
"""
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from contextlib import asynccontextmanager
import uvicorn
from config import settings
from database import init_db, close_db
from services import DoclingParser, Section
from services.parser import process_document


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


class ParseDocumentResponse(BaseModel):
    """Ответ на запрос парсинга документа."""
    message: str
    document_id: str
    status: str = "processing"


@app.post("/api/v1/parse", response_model=ParseDocumentResponse)
async def parse_document_background(
    request: ParseDocumentRequest,
    background_tasks: BackgroundTasks
):
    """
    Запускает парсинг документа в фоне и сохраняет секции в БД.
    
    Args:
        request: Запрос с document_id и file_path (или file_url)
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
            file_path=request.file_path
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


if __name__ == "__main__":
    # Запуск сервера через Uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,  # Автоперезагрузка в режиме отладки
    )

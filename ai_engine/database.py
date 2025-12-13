"""
Настройка асинхронного подключения к PostgreSQL (Supabase).
Использует SQLAlchemy с asyncpg драйвером.
"""
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import NullPool
from config import settings

# Базовый класс для моделей
Base = declarative_base()

# Создаем асинхронный движок с поддержкой SSL для Supabase
# Supabase требует параметр ssl=require в connection string
# Для asyncpg необходимо явно указать ssl в connect_args
# asyncpg поддерживает ssl='require' как строку, ssl=True или ssl.SSLContext
def get_engine_kwargs():
    """Возвращает параметры для создания движка с учетом SSL для Supabase."""
    kwargs = {
        "poolclass": NullPool,
        "echo": settings.DEBUG,
        "future": True,
    }
    
    # Для Supabase всегда требуется SSL
    # asyncpg требует явного указания ssl параметра в connect_args
    # Используем ssl='require' для обязательного SSL соединения
    # Это эквивалентно sslmode=require в стандартном PostgreSQL connection string
    kwargs["connect_args"] = {"ssl": "require"}
    
    return kwargs

engine = create_async_engine(
    settings.DATABASE_URL,
    **get_engine_kwargs()
)

# Создаем фабрику сессий
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncSession:
    """
    Dependency для получения асинхронной сессии БД.
    Используется в FastAPI endpoints.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def init_db():
    """
    Инициализация базы данных.
    Создает все таблицы, определенные в моделях.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def close_db():
    """
    Закрытие соединений с базой данных.
    """
    await engine.dispose()

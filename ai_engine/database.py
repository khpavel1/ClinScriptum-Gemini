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

# Валидация конфигурации БД перед созданием движка
try:
    settings.validate_database_config()
except ValueError as e:
    # Выводим понятное сообщение об ошибке
    print(f"\n{'='*60}")
    print("ОШИБКА КОНФИГУРАЦИИ БАЗЫ ДАННЫХ")
    print(f"{'='*60}")
    print(str(e))
    print(f"{'='*60}\n")
    raise

# Отладочная информация о connection string (без пароля)
if settings.DATABASE_URL:
    db_url = settings.DATABASE_URL
    # Маскируем пароль для безопасного вывода
    try:
        if "@" in db_url and "://" in db_url:
            parts = db_url.split("://")
            if len(parts) == 2:
                protocol = parts[0]
                rest = parts[1]
                if "@" in rest:
                    user_pass, host_db = rest.split("@", 1)
                    if ":" in user_pass:
                        user = user_pass.split(":")[0]
                        masked_url = f"{protocol}://{user}:***@{host_db}"
                        print(f"[Database Config] Connection string: {masked_url}")
                    else:
                        print(f"[Database Config] Connection string: {protocol}://{user_pass}@{host_db}")
                else:
                    print(f"[Database Config] Connection string: {db_url[:50]}...")
            else:
                print(f"[Database Config] Connection string: {db_url[:50]}...")
        else:
            print(f"[Database Config] Connection string: {db_url[:50]}...")
    except Exception:
        print(f"[Database Config] Connection string: (не удалось распарсить)")
    
    # Проверка формата для Supabase
    db_url_lower = db_url.lower()
    if "pooler.supabase.com" in db_url_lower:
        if ":6543" in db_url_lower:
            # Connection pooling - должен быть postgres.[project-ref]
            if "postgres." in db_url and "@" in db_url:
                user_part = db_url.split("://")[1].split("@")[0].split(":")[0]
                if user_part == "postgres":
                    print("\n" + "!"*60)
                    print("ВНИМАНИЕ: Неверный формат пользователя для Supabase connection pooling!")
                    print("!"*60)
                    print("Для порта 6543 (connection pooling) имя пользователя должно быть:")
                    print("  postgres.[project-ref]")
                    print("а не просто:")
                    print("  postgres")
                    print("\nИсправьте DATABASE_URL или используйте SUPABASE_PROJECT_REF")
                    print("!"*60 + "\n")

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
    
    # Определяем, нужен ли SSL на основе DATABASE_URL
    # Для Supabase (pooler.supabase.com) всегда требуется SSL
    # Для локальных подключений (localhost, 127.0.0.1) SSL не требуется
    database_url = settings.DATABASE_URL.lower()
    is_supabase = "pooler.supabase.com" in database_url or "supabase.co" in database_url
    is_local = "localhost" in database_url or "127.0.0.1" in database_url
    
    if is_supabase:
        # Для Supabase всегда требуется SSL
        # Отключаем кэш prepared statements для pgbouncer (connection pooling)
        # pgbouncer с pool_mode "transaction" или "statement" не поддерживает prepared statements
        kwargs["connect_args"] = {
            "ssl": "require",
            "statement_cache_size": 0,  # Отключаем кэш для pgbouncer
        }
    elif is_local:
        # Для локальной БД SSL не требуется
        kwargs["connect_args"] = {"ssl": False}
    else:
        # По умолчанию требуем SSL для безопасности
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
    Включает расширение pgvector для работы с векторами.
    """
    async with engine.begin() as conn:
        # Включаем расширение pgvector
        from sqlalchemy import text
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        await conn.run_sync(Base.metadata.create_all)


async def close_db():
    """
    Закрытие соединений с базой данных.
    """
    await engine.dispose()

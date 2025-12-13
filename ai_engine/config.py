"""
Конфигурация приложения.
Загрузка переменных окружения из .env файла.
"""
import os
from typing import Optional
from dotenv import load_dotenv

# Загружаем переменные окружения из .env файла
load_dotenv()


class Settings:
    """Настройки приложения."""
    
    # База данных
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://user:password@localhost:5432/dbname"
    )
    
    # Yandex API
    YANDEX_API_KEY: Optional[str] = os.getenv("YANDEX_API_KEY")
    
    # Supabase
    SUPABASE_URL: Optional[str] = os.getenv("SUPABASE_URL")
    SUPABASE_KEY: Optional[str] = os.getenv("SUPABASE_KEY")
    SUPABASE_STORAGE_BUCKET: str = os.getenv("SUPABASE_STORAGE_BUCKET", "documents")
    
    # Настройки приложения
    APP_NAME: str = "AI Engine"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"


# Глобальный экземпляр настроек
settings = Settings()

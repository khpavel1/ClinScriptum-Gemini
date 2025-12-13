"""
Конфигурация приложения.
Загрузка переменных окружения из .env файла.
"""
import os
from typing import Optional
from urllib.parse import quote_plus
from dotenv import load_dotenv

# Загружаем переменные окружения из .env файла
load_dotenv()


class Settings:
    """Настройки приложения."""
    
    # База данных (Supabase PostgreSQL)
    # Поддерживаются три способа настройки (в порядке приоритета):
    # 1. Полный connection string через DATABASE_URL
    # 2. Автоматическая сборка из SUPABASE_PROJECT_REF + SUPABASE_DB_PASSWORD
    # 3. Отдельные переменные (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
    #
    # Формат connection string для Supabase:
    # postgresql+asyncpg://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres
    #
    # Получить connection string можно в Supabase Dashboard:
    # Settings -> Database -> Connection string -> Connection pooling (для 6543) или Direct connection (для 5432)
    
    # Способ 1: Полный connection string (приоритет)
    _database_url: Optional[str] = os.getenv("DATABASE_URL")
    
    # Способ 2: Отдельные параметры подключения
    DB_HOST: str = os.getenv("DB_HOST", os.getenv("SUPABASE_DB_HOST", ""))
    DB_PORT: str = os.getenv("DB_PORT", os.getenv("SUPABASE_DB_PORT", "5432"))
    DB_USER: str = os.getenv("DB_USER", os.getenv("SUPABASE_DB_USER", "postgres"))
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_NAME: str = os.getenv("DB_NAME", os.getenv("SUPABASE_DB_NAME", "postgres"))
    
    # Способ 3: Автоматическая сборка через Supabase project reference
    # Если указан SUPABASE_PROJECT_REF, собираем connection string автоматически
    SUPABASE_PROJECT_REF: Optional[str] = os.getenv("SUPABASE_PROJECT_REF")
    SUPABASE_DB_PASSWORD: Optional[str] = os.getenv("SUPABASE_DB_PASSWORD")
    SUPABASE_DB_REGION: str = os.getenv("SUPABASE_DB_REGION", "us-east-1")
    SUPABASE_DB_POOLER_PORT: str = os.getenv("SUPABASE_DB_POOLER_PORT", "6543")  # Connection pooling
    SUPABASE_DB_DIRECT_PORT: str = os.getenv("SUPABASE_DB_DIRECT_PORT", "5432")  # Direct connection
    USE_DB_POOLER: bool = os.getenv("USE_DB_POOLER", "true").lower() == "true"
    
    @property
    def DATABASE_URL(self) -> str:
        """
        Возвращает connection string к базе данных.
        Приоритет:
        1. DATABASE_URL (если установлен)
        2. Автоматическая сборка из SUPABASE_PROJECT_REF
        3. Сборка из отдельных параметров (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
        """
        # Способ 1: Используем полный connection string, если он указан
        if self._database_url:
            return self._database_url
        
        # Способ 2: Автоматическая сборка из Supabase project reference
        if self.SUPABASE_PROJECT_REF and self.SUPABASE_DB_PASSWORD:
            port = self.SUPABASE_DB_POOLER_PORT if self.USE_DB_POOLER else self.SUPABASE_DB_DIRECT_PORT
            user = f"postgres.{self.SUPABASE_PROJECT_REF}"
            host = f"aws-0-{self.SUPABASE_DB_REGION}.pooler.supabase.com"
            password = quote_plus(self.SUPABASE_DB_PASSWORD)
            return f"postgresql+asyncpg://{user}:{password}@{host}:{port}/postgres"
        
        # Способ 3: Сборка из отдельных параметров (DB_HOST, DB_PASSWORD и т.д.)
        if self.DB_HOST and self.DB_PASSWORD:
            password = quote_plus(self.DB_PASSWORD)
            user = quote_plus(self.DB_USER) if self.DB_USER else "postgres"
            db_name = quote_plus(self.DB_NAME) if self.DB_NAME else "postgres"
            return f"postgresql+asyncpg://{user}:{password}@{self.DB_HOST}:{self.DB_PORT}/{db_name}"
        
        # Если ничего не настроено, возвращаем пустую строку
        return ""
    
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
    
    def validate_database_config(self) -> None:
        """
        Проверяет, что настройки базы данных корректны.
        Вызывает ValueError с понятным сообщением, если конфигурация неполная.
        """
        db_url = self.DATABASE_URL
        if not db_url:
            error_msg = (
                "База данных не настроена. Установите один из вариантов:\n"
                "1. DATABASE_URL - полный connection string\n"
                "2. SUPABASE_PROJECT_REF + SUPABASE_DB_PASSWORD\n"
                "3. DB_HOST + DB_PASSWORD (и опционально DB_PORT, DB_USER, DB_NAME)\n\n"
                "Примеры для .env файла:\n"
                "# Вариант 1 (полный connection string):\n"
                "DATABASE_URL=postgresql+asyncpg://postgres.[ref]:[pass]@aws-0-[region].pooler.supabase.com:6543/postgres\n\n"
                "# Вариант 2 (Supabase project reference):\n"
                "SUPABASE_PROJECT_REF=your-project-ref\n"
                "SUPABASE_DB_PASSWORD=your-db-password\n"
                "SUPABASE_DB_REGION=us-east-1\n"
                "USE_DB_POOLER=true\n\n"
                "# Вариант 3 (отдельные параметры):\n"
                "DB_HOST=aws-0-us-east-1.pooler.supabase.com\n"
                "DB_PORT=6543\n"
                "DB_USER=postgres.your-project-ref\n"
                "DB_PASSWORD=your-db-password\n"
                "DB_NAME=postgres"
            )
            raise ValueError(error_msg)
        
        # Проверяем формат connection string
        if not db_url.startswith(("postgresql://", "postgresql+asyncpg://")):
            raise ValueError(
                f"Неверный формат DATABASE_URL. Ожидается postgresql:// или postgresql+asyncpg://, "
                f"получено: {db_url[:30]}..."
            )


# Глобальный экземпляр настроек
settings = Settings()

# Проверяем конфигурацию БД при импорте (только предупреждение, не ошибка)
if not settings.DATABASE_URL:
    import warnings
    warnings.warn(
        "DATABASE_URL не настроен. Установите переменные окружения для подключения к базе данных.",
        UserWarning
    )

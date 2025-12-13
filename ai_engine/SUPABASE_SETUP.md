# Настройка подключения к Supabase для AI Engine

## Ошибка "Tenant or user not found"

Эта ошибка означает, что connection string к Supabase настроен неправильно.

## Как получить правильный connection string

### Способ 1: Из Supabase Dashboard (рекомендуется)

1. Откройте [Supabase Dashboard](https://app.supabase.com)
2. Выберите ваш проект
3. Перейдите в **Settings** → **Database**
4. Найдите раздел **Connection string**
5. Выберите вкладку **Connection pooling** (порт 6543)
6. Скопируйте connection string
7. **ВАЖНО**: Замените `postgresql://` на `postgresql+asyncpg://`
8. Замените `[YOUR-PASSWORD]` на ваш реальный пароль базы данных

**Пример правильного формата:**
```
postgresql+asyncpg://postgres.your-project-ref:your-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

### Способ 2: Автоматическая сборка через переменные окружения

Создайте файл `ai_engine/.env`:

```env
# Получите project-ref из Supabase Dashboard → Settings → General → Reference ID
SUPABASE_PROJECT_REF=your-project-ref

# Пароль базы данных (устанавливается при создании проекта)
SUPABASE_DB_PASSWORD=your-db-password

# Регион (обычно us-east-1, eu-west-1 и т.д.)
SUPABASE_DB_REGION=us-east-1

# Использовать connection pooling (рекомендуется)
USE_DB_POOLER=true
```

### Способ 3: Полный connection string в .env

```env
DATABASE_URL=postgresql+asyncpg://postgres.your-project-ref:your-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

## Важные моменты

1. **Формат пользователя для connection pooling (порт 6543):**
   - ✅ Правильно: `postgres.your-project-ref`
   - ❌ Неправильно: `postgres`

2. **Формат пользователя для прямого подключения (порт 5432):**
   - ✅ Правильно: `postgres`
   - ❌ Неправильно: `postgres.your-project-ref`

3. **Префикс для asyncpg:**
   - Должен быть: `postgresql+asyncpg://`
   - Не просто: `postgresql://`

4. **Где найти project-ref:**
   - Supabase Dashboard → Settings → General → Reference ID

5. **Где найти пароль базы данных:**
   - Supabase Dashboard → Settings → Database → Database password
   - Если забыли пароль, можно сбросить его в том же разделе

## Проверка

После настройки перезапустите сервер. Вы должны увидеть:
```
[Database Config] Connection string: postgresql+asyncpg://postgres.your-ref:***@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

Если видите предупреждение о неправильном формате пользователя, исправьте connection string согласно инструкции выше.

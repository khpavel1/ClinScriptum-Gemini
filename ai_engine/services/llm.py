"""
Сервис для работы с LLM и эмбеддингами.
Поддерживает YandexGPT и OpenAI-compatible API.
"""
from typing import List, Optional
import os
from openai import AsyncOpenAI
from config import settings


class LLMClient:
    """
    Клиент для работы с LLM и эмбеддингами.
    Поддерживает YandexGPT и OpenAI-compatible API.
    """
    
    def __init__(self):
        """Инициализация клиента."""
        self.api_key = settings.YANDEX_API_KEY or os.getenv("OPENAI_API_KEY")
        self.base_url = os.getenv("YANDEX_API_URL") or os.getenv("OPENAI_BASE_URL") or "https://api.openai.com/v1"
        
        # Используем OpenAI-compatible client (работает с YandexGPT и OpenAI)
        self.client = AsyncOpenAI(
            api_key=self.api_key,
            base_url=self.base_url
        )
        
        # Модели по умолчанию
        self.embedding_model = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
        self.llm_model = os.getenv("LLM_MODEL", "gpt-4o-mini")
    
    async def get_embedding(self, text: str) -> List[float]:
        """
        Получает векторное представление текста (эмбеддинг).
        
        Args:
            text: Текст для векторизации
            
        Returns:
            Список чисел (вектор размерности 1536)
            
        Raises:
            Exception: Если произошла ошибка при получении эмбеддинга
        """
        try:
            # Для YandexGPT используем специальный endpoint
            if "yandex" in self.base_url.lower():
                # YandexGPT embeddings endpoint
                response = await self.client.embeddings.create(
                    model="text-search-doc",
                    input=text
                )
            else:
                # OpenAI-compatible endpoint
                response = await self.client.embeddings.create(
                    model=self.embedding_model,
                    input=text
                )
            
            return response.data[0].embedding
        except Exception as e:
            raise Exception(f"Ошибка при получении эмбеддинга: {str(e)}")
    
    async def generate_text(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.7,
        max_tokens: Optional[int] = None
    ) -> str:
        """
        Генерирует текст с помощью LLM.
        
        Args:
            system_prompt: Системный промпт (инструкции для модели)
            user_prompt: Пользовательский промпт (контекст и запрос)
            temperature: Температура генерации (0.0-1.0)
            max_tokens: Максимальное количество токенов в ответе
            
        Returns:
            Сгенерированный текст
            
        Raises:
            Exception: Если произошла ошибка при генерации
        """
        try:
            response = await self.client.chat.completions.create(
                model=self.llm_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=temperature,
                max_tokens=max_tokens
            )
            
            return response.choices[0].message.content
        except Exception as e:
            raise Exception(f"Ошибка при генерации текста: {str(e)}")

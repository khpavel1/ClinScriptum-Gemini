"""
Абстрактный базовый класс для парсеров документов.
"""
from abc import ABC, abstractmethod
from typing import List
from .types import Section


class BaseParser(ABC):
    """
    Базовый класс для всех парсеров документов.
    Определяет общий интерфейс для парсинга файлов в секции.
    """
    
    @abstractmethod
    async def parse(self, file_path: str) -> List[Section]:
        """
        Парсит документ по указанному пути и возвращает список секций.
        
        Args:
            file_path: Путь к файлу для парсинга
            
        Returns:
            Список секций документа
            
        Raises:
            FileNotFoundError: Если файл не найден
            ValueError: Если файл не может быть обработан
        """
        pass

"""
Prompt Manager - Singleton для управления промптами из внешних файлов.
Позволяет Prompt Engineers изменять инструкции без изменения Python кода.
"""
import os
import yaml
from typing import Dict, Any, Optional
from pathlib import Path


class PromptManager:
    """
    Singleton класс для загрузки и управления промптами из YAML файла.
    Загружает промпты при первом обращении и кэширует их.
    """
    
    _instance: Optional['PromptManager'] = None
    _prompts: Optional[Dict[str, Any]] = None
    _yaml_path: Optional[Path] = None
    
    def __new__(cls):
        """
        Реализация паттерна Singleton.
        """
        if cls._instance is None:
            cls._instance = super(PromptManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        """
        Инициализация менеджера промптов.
        Загружает YAML файл при первом создании экземпляра.
        """
        if self._prompts is None:
            self._load_prompts()
    
    def _load_prompts(self) -> None:
        """
        Загружает промпты из YAML файла.
        Ищет файл prompts.yaml в директории ai_engine.
        """
        # Определяем путь к файлу prompts.yaml
        # Файл должен находиться в корне ai_engine
        current_file = Path(__file__)
        ai_engine_dir = current_file.parent.parent
        yaml_path = ai_engine_dir / "prompts.yaml"
        
        if not yaml_path.exists():
            raise FileNotFoundError(
                f"Prompts file not found: {yaml_path}. "
                "Please create prompts.yaml in ai_engine directory."
            )
        
        self._yaml_path = yaml_path
        
        try:
            with open(yaml_path, 'r', encoding='utf-8') as f:
                self._prompts = yaml.safe_load(f)
        except yaml.YAMLError as e:
            raise ValueError(f"Error parsing prompts.yaml: {str(e)}")
        except Exception as e:
            raise RuntimeError(f"Error loading prompts.yaml: {str(e)}")
    
    def reload(self) -> None:
        """
        Перезагружает промпты из YAML файла.
        Полезно для обновления промптов без перезапуска приложения.
        """
        self._prompts = None
        self._load_prompts()
    
    def get_prompt(self, key: str, **kwargs) -> str:
        """
        Получает промпт по ключу и форматирует его с переданными переменными.
        
        Ключ должен быть в формате "category.subkey", например:
        - "generation.system_role"
        - "generation.section_generation"
        - "extraction.extract_globals"
        
        Args:
            key: Ключ промпта в формате "category.subkey"
            **kwargs: Переменные для форматирования промпта
            
        Returns:
            Отформатированная строка промпта
            
        Raises:
            KeyError: Если ключ не найден в структуре промптов
            ValueError: Если промпт не является строкой
        """
        if self._prompts is None:
            self._load_prompts()
        
        # Разбиваем ключ на категорию и подключач
        parts = key.split('.')
        if len(parts) != 2:
            raise ValueError(
                f"Invalid prompt key format: '{key}'. "
                "Expected format: 'category.subkey'"
            )
        
        category, subkey = parts
        
        # Получаем категорию
        if category not in self._prompts:
            raise KeyError(f"Category '{category}' not found in prompts")
        
        category_data = self._prompts[category]
        
        # Получаем подключач
        if subkey not in category_data:
            raise KeyError(
                f"Subkey '{subkey}' not found in category '{category}'. "
                f"Available subkeys: {list(category_data.keys())}"
            )
        
        prompt_template = category_data[subkey]
        
        if not isinstance(prompt_template, str):
            raise ValueError(
                f"Prompt '{key}' is not a string. Got type: {type(prompt_template)}"
            )
        
        # Форматируем промпт с переданными переменными
        try:
            return prompt_template.format(**kwargs)
        except KeyError as e:
            raise ValueError(
                f"Missing required variable for prompt '{key}': {e}. "
                f"Provided variables: {list(kwargs.keys())}"
            )
    
    def get_version(self) -> Optional[str]:
        """
        Возвращает версию промптов из YAML файла.
        
        Returns:
            Версия промптов или None, если версия не указана
        """
        if self._prompts is None:
            self._load_prompts()
        
        return self._prompts.get('version')
    
    def get_yaml_path(self) -> Optional[Path]:
        """
        Возвращает путь к YAML файлу с промптами.
        
        Returns:
            Path к файлу prompts.yaml или None, если файл не загружен
        """
        return self._yaml_path

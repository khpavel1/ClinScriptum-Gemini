# 06. Экспорт и Форматирование

## 1. Форматы
*   **DOCX:** Сборка документа из HTML (Tiptap) с применением корпоративных стилей через Pandoc.

## 2. Сервис Экспорта (`services/exporter.py`)

### 2.1 Основная функция

**Класс `Exporter`** - сервис для экспорта готовых документов (deliverables) в различные форматы:

*   `export_deliverable_to_docx(deliverable_id, db, reference_docx=None) -> bytes` - экспортирует deliverable в формат DOCX используя Pandoc
*   `export_deliverable_to_docx_file(deliverable_id, db, output_path, reference_docx=None) -> str` - экспортирует deliverable в DOCX файл на диске

### 2.2 Процесс экспорта

1. **Получение секций:** Получает все `DeliverableSections` для документа, отсортированные по `order_index`
2. **Объединение HTML:** Объединяет `content_html` всех секций в один большой HTML документ
3. **Конвертация:** Использует `pypandoc.convert_text` для конвертации HTML в DOCX
4. **Применение шаблона:** Опционально применяет корпоративный шаблон (`reference.docx`) через параметр `--reference-doc` в Pandoc
5. **Возврат:** Возвращает бинарные данные DOCX файла

### 2.3 API Endpoint

**Эндпоинт `GET /api/v1/export/{deliverable_id}`**

Экспортирует deliverable в формат DOCX и возвращает файл как поток.

**Параметры:**
*   `deliverable_id` (UUID, path parameter) - UUID документа для экспорта
*   `reference_docx` (string, query parameter, опционально) - Путь к шаблону DOCX с корпоративными стилями

**Ответ:**
*   `StreamingResponse` с DOCX файлом
*   Content-Type: `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
*   Content-Disposition: `attachment; filename="{название_документа}.docx"`

**Пример использования:**
```bash
# Экспорт без шаблона
GET /api/v1/export/123e4567-e89b-12d3-a456-426614174000

# Экспорт с корпоративным шаблоном
GET /api/v1/export/123e4567-e89b-12d3-a456-426614174000?reference_docx=/path/to/template.docx
```

**Обработка ошибок:**
*   `404` - Deliverable не найден или нет секций для экспорта
*   `500` - Ошибка при конвертации через Pandoc или неожиданная ошибка

### 2.4 Требования

*   **Pandoc:** Должен быть установлен в системе (pypandoc - это только Python обертка)
*   **Зависимости:** `pypandoc` добавлен в `requirements.txt`

## 3. Особенности экспорта таблиц
*   Поскольку мы парсим и генерируем таблицы в Markdown/HTML, при экспорте в Word через Pandoc они становятся "живыми" таблицами Word (не картинками).
*   Pandoc корректно обрабатывает HTML таблицы и конвертирует их в нативные таблицы Word.

## 4. Audit Log Export
*   Вместе с документом можно выгрузить "Audit Trail": CSV файл, где для каждого раздела указано:
    *   Какие исходные секции использовались (`used_source_section_ids` из `deliverable_sections`)
    *   Какое правило маппинга было применено (`mapping_logic_used` из `GenerationResult`)
    *   История изменений секции (`deliverable_section_history` с информацией о пользователе, времени и причине изменения)
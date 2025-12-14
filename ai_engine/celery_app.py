"""
Celery application configuration.
Initializes Celery with Redis as broker and backend.
"""
from celery import Celery
from config import settings

# Create Celery app instance
celery_app = Celery(
    "ai_engine",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
    include=["tasks"],  # Include tasks module
)

# Celery configuration
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=30 * 60,  # 30 minutes max task time
    task_soft_time_limit=25 * 60,  # 25 minutes soft limit
    worker_prefetch_multiplier=1,  # Process one task at a time for better resource control
    worker_max_tasks_per_child=50,  # Restart worker after 50 tasks to prevent memory leaks
)

# Dockerfile
FROM python:3.9-slim

# Аргументы сборки
ARG MINIO_URL
ARG BUCKET_NAME
ARG MODEL_NAME
ARG MODEL_VERSION
ARG BUILD_DATE
ARG BUILD_ID
ARG GRADIO_SERVER_PORT=7860

# Переменные окружения
ENV MINIO_URL=${MINIO_URL}
ENV BUCKET_NAME=${BUCKET_NAME}
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_VERSION=${MODEL_VERSION}
ENV BUILD_DATE=${BUILD_DATE}
ENV BUILD_ID=${BUILD_ID}
ENV GRADIO_SERVER_PORT=${GRADIO_SERVER_PORT}

WORKDIR /app

# Устанавливаем зависимости
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gradio>=3.50.2

# Копируем файлы приложения
COPY . .

# Открываем порт для Gradio
EXPOSE ${GRADIO_SERVER_PORT}

# Запускаем приложение
CMD ["python", "app.py"]

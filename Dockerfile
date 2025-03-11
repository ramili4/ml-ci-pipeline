# Use Python 3.9 slim image as the base
FROM python:3.9-slim

# Build arguments
ARG MINIO_URL
ARG BUCKET_NAME
ARG MODEL_NAME
ARG MODEL_VERSION
ARG BUILD_DATE
ARG BUILD_ID
ARG API_PORT=5000

# Environment variables
ENV MINIO_URL=${MINIO_URL}
ENV BUCKET_NAME=${BUCKET_NAME}
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_VERSION=${MODEL_VERSION}
ENV BUILD_DATE=${BUILD_DATE}
ENV BUILD_ID=${BUILD_ID}
ENV API_PORT=${API_PORT}

# Set working directory inside the container
WORKDIR /app

# Ensure model directory exists inside the container
RUN mkdir -p /models && chmod -R 777 /models

# Copy requirements.txt and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir flask gunicorn minio \
    && pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Copy the downloaded model from Jenkins agent's build context
COPY tmp-models/${MODEL_NAME} /models/${MODEL_NAME}

# Copy application files into the container
COPY src/app.py /app/app.py

# Set permissions for security
RUN useradd -m appuser && chown -R appuser:appuser /app /models

# Expose the port for the Flask API
EXPOSE ${API_PORT}

# Switch to non-root user
USER appuser

# Run Gunicorn as the entry point
ENTRYPOINT ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:5000", "app:app"]

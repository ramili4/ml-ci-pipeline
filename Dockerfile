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

# Copy requirements.txt and install dependencies (without torch)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir flask gunicorn \
    # Install CPU-only version of PyTorch, TorchVision, and Torchaudio
    && pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    
# Download model from MinIO securely
RUN python -c "import os; from minio import Minio; \
    client = Minio(os.getenv('MINIO_URL', 'localhost:9000').replace('http://', ''), \
                   access_key=os.getenv('MINIO_ACCESS_KEY'), \
                   secret_key=os.getenv('MINIO_SECRET_KEY'), \
                   secure=False); \
    bucket = os.getenv('BUCKET_NAME', 'models'); \
    prefix = os.getenv('MODEL_NAME', 'bert-tiny') + '/'; \
    os.makedirs(f'/models/{prefix}', exist_ok=True); \
    for obj in client.list_objects(bucket, prefix=prefix, recursive=True): \
        client.fget_object(bucket, obj.object_name, f'/models/{obj.object_name.split(\"/\", 1)[-1]}')"


# Copy application files into the container
COPY . .

# Expose the port for the Flask API
EXPOSE ${API_PORT}

# Set the entrypoint to run the Flask application
CMD ["python", "app.py"]

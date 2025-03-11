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
ARG MINIO_ACCESS_KEY
ARG MINIO_SECRET_KEY

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
    && pip install --no-cache-dir flask gunicorn minio \
    # Install CPU-only version of PyTorch, TorchVision, and Torchaudio
    && pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Download model from MinIO securely
RUN python -c "import os; \
    from minio import Minio; \
    minio_url = os.getenv('MINIO_URL', 'localhost:9000').replace('http://', ''); \
    bucket = os.getenv('BUCKET_NAME', 'models'); \
    model_name = os.getenv('MODEL_NAME', 'bert-tiny'); \
    prefix = model_name + '/'; \
    model_dir = f'/models/{model_name}'; \
    os.makedirs(model_dir, exist_ok=True); \
    print(f'Downloading model {model_name} from {bucket}'); \
    client = Minio(minio_url, access_key=access_key, secret_key=secret_key, secure=False); \
    objects_found = False; \
    for obj in client.list_objects(bucket, prefix=prefix, recursive=True): \
        objects_found = True; \
        object_name = obj.object_name; \
        relative_path = object_name[len(prefix):] if prefix in object_name else object_name; \
        destination = f'{model_dir}/{relative_path}'; \
        os.makedirs(os.path.dirname(destination), exist_ok=True) if '/' in relative_path else None; \
        print(f'Downloading {object_name} to {destination}'); \
        client.fget_object(bucket, object_name, destination); \
    if not objects_found: \
        raise Exception(f'No objects found for model {model_name} in bucket {bucket}')"

# Copy application files into the container
COPY . .

# Expose the port for the Flask API
EXPOSE ${API_PORT}

# Set the entrypoint to run the Flask application
CMD ["python", "app.py"]

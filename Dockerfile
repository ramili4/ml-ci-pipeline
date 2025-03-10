# Use Python 3.9 slim image as the base
FROM python:3.9-slim

# Build arguments
ARG MINIO_URL
ARG BUCKET_NAME
ARG MODEL_NAME
ARG MODEL_VERSION
ARG BUILD_DATE
ARG BUILD_ID
ARG GRADIO_SERVER_PORT=7860

# Environment variables
ENV MINIO_URL=${MINIO_URL}
ENV BUCKET_NAME=${BUCKET_NAME}
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_VERSION=${MODEL_VERSION}
ENV BUILD_DATE=${BUILD_DATE}
ENV BUILD_ID=${BUILD_ID}
ENV GRADIO_SERVER_PORT=${GRADIO_SERVER_PORT}

# Set working directory inside the container
WORKDIR /app

# Copy requirements.txt and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gradio>=3.50.2 \
    # Install CPU-only version of PyTorch
    && pip install --no-cache-dir torch==2.1.0+cpu  # Ensure CPU version of PyTorch is installed

# Copy all application files into the container
COPY . .

# Expose the port for Gradio server
EXPOSE ${GRADIO_SERVER_PORT}

# Run the application
CMD ["python", "app.py"]

pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        NEXUS_HOST = "localhost"
        NEXUS_HTTP_PORT = "8081"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_HTTP_PORT}/repository/docker-hosted"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        MODEL_REPO = "google/bert_uncased_L-2_H-128_A-2"
        DOCKER_HOST = "unix:///var/run/docker.sock"
    }

    stages {
        stage('Build Docker Image') {
            steps {
                script {
                    def dockerfileContent = '''
                    FROM python:3.9-slim

                    ARG MINIO_URL
                    ARG BUCKET_NAME
                    ARG MODEL_NAME

                    ENV MINIO_URL=${MINIO_URL}
                    ENV BUCKET_NAME=${BUCKET_NAME}
                    ENV MODEL_NAME=${MODEL_NAME}

                    WORKDIR /app

                    COPY . .

                    CMD ["python", "app.py"]
                    '''
                    writeFile file: 'Dockerfile', text: dockerfileContent
                    echo "Dockerfile created successfully!"

                    sh """
                        docker build \
                            --build-arg MINIO_URL=${MINIO_URL} \
                            --build-arg BUCKET_NAME=${BUCKET_NAME} \
                            --build-arg MODEL_NAME=${MODEL_NAME} \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    """
                    echo "Successfully built Docker image"
                }
            }
        }

        stage('Push Image to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        sh """
                            docker login -u \$NEXUS_USER -p \$NEXUS_PASSWORD ${REGISTRY}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        """
                        echo "Successfully pushed image to Nexus"
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    sh """
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                        docker rmi ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                    """
                    echo "Successfully cleaned up workspace"
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline executed successfully!"
        }
        failure {
            echo "Pipeline failed! Check the logs for details."
        }
        always {
            cleanWs()
        }
    }
}

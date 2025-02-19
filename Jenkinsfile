pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"  
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"  
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        DOCKER_HOST = "unix:///var/run/docker.sock"
    }

    stages {
        stage('Read Model Config') {
            steps {
                script {
                    def modelConfig = readYaml file: 'model-config.yaml'
                    env.MODEL_NAME = modelConfig.model_name ?: "bert-tiny"
                    env.HF_REPO = modelConfig.huggingface_repo ?: "prajjwal1/bert-tiny"
                    env.IMAGE_TAG = "latest"
                    env.IMAGE_NAME = "ml-model-${env.MODEL_NAME}" // Dynamically set image name
                    echo "Using model: ${env.MODEL_NAME} from repo: ${env.HF_REPO}"
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    sh """
                        mkdir -p models/${env.MODEL_NAME}
                        set -e

                        for file in pytorch_model.bin config.json vocab.txt; do
                            curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                                -L https://huggingface.co/${env.HF_REPO}/resolve/main/\$file \
                                -o models/${env.MODEL_NAME}/\$file
                        done
                    """
                    echo "Successfully downloaded model: ${env.MODEL_NAME}"
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                script {
                    def modelPath = "${WORKSPACE}/models/${env.MODEL_NAME}"
                    def modelFiles = sh(script: "ls -A ${modelPath} | wc -l", returnStdout: true).trim()

                    if (modelFiles.toInteger() == 0) {
                        error("Error: Model directory is empty! Exiting.")
                    }

                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_USER', passwordVariable: 'MINIO_PASS')]) {
                        sh """
                            /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS} --quiet || true

                            if ! /usr/local/bin/mc ls myminio/${BUCKET_NAME} >/dev/null 2>&1; then
                                echo "Creating bucket ${BUCKET_NAME}..."
                                /usr/local/bin/mc mb myminio/${BUCKET_NAME}
                            fi

                            /usr/local/bin/mc cp --recursive ${modelPath} myminio/${BUCKET_NAME}/
                        """
                    }
                }
            }
        }

        stage('Create Dockerfile') {
            steps {
                script {
                    def dockerfileContent = """
                    FROM python:3.9-slim

                    ARG MINIO_URL
                    ARG BUCKET_NAME
                    ARG MODEL_NAME

                    ENV MINIO_URL=\${MINIO_URL}
                    ENV BUCKET_NAME=\${BUCKET_NAME}
                    ENV MODEL_NAME=\${MODEL_NAME}

                    WORKDIR /app

                    COPY . . 

                    CMD ["python", "app.py"]
                    """
                    writeFile file: 'Dockerfile', text: dockerfileContent
                    echo "Dockerfile created successfully!"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def modelNameLower = env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")
                    def imageName = "ml-model-${modelNameLower}"
                    def imageTag = env.IMAGE_TAG ?: "latest"
                    sh """
                        docker build \
                            --build-arg MINIO_URL=${MINIO_URL} \
                            --build-arg BUCKET_NAME=${BUCKET_NAME} \
                            --build-arg MODEL_NAME=${env.MODEL_NAME} \
                            -t ${env.IMAGE_NAME}:${IMAGE_TAG} .
                    """
                    env.IMAGE_NAME = imageName // Update IMAGE_NAME for later use
                    echo "Successfully built Docker image: ${env.IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }

        stage('Tag and Push Image to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        sh """
                            echo "$NEXUS_PASSWORD" | docker login -u "$NEXUS_USER" --password-stdin http://${REGISTRY}
                            docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                        """
                        echo "Successfully pushed image: ${env.IMAGE_NAME} to Nexus"
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    sh """
                        echo "Cleaning up local models..."
                        rm -rf models/${env.MODEL_NAME}

                        echo "Removing unused Docker images..."
                        docker images -q ${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi || true
                    """
                    echo "Cleanup complete"
                }
            }
        }
    } // Close 'stages' block
} // Close 'pipeline' block

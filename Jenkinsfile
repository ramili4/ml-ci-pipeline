pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"  
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"  
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        MODEL_REPO = "google/bert_uncased_L-2_H-128_A-2"
        DOCKER_HOST = "unix:///var/run/docker.sock"
    }

    stages {
        stage('Read Model Config') {
            steps {
                script {
                    def modelConfig = readYaml file: 'model-config.yaml'
                    env.MODEL_NAME = modelConfig.model_name ?: "bert-tiny"
                    echo "Using model: ${env.MODEL_NAME}"
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    sh """
                        mkdir -p models/${env.MODEL_NAME}
                        set -e

                        curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/pytorch_model.bin \
                            -o models/${env.MODEL_NAME}/pytorch_model.bin

                        curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/config.json \
                            -o models/${env.MODEL_NAME}/config.json

                        curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/vocab.txt \
                            -o models/${env.MODEL_NAME}/vocab.txt
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
                    sh """
                        docker build \
                            --build-arg MINIO_URL=${MINIO_URL} \
                            --build-arg BUCKET_NAME=${BUCKET_NAME} \
                            --build-arg MODEL_NAME=${env.MODEL_NAME} \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    """
                    echo "Successfully built Docker image"
                }
            }
        }

        stage('Tag and Push Image to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    sh '''
                        echo "$NEXUS_PASSWORD" | docker login -u "$NEXUS_USER" --password-stdin http://${REGISTRY}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                    echo "Successfully pushed image to Nexus"
                }
            }
        }
        
        stage('Cleanup') {
            steps {
                script {
                    sh '''
                        rm -rf models/''' + "${env.MODEL_NAME}" + '''
                        docker images -q ''' + "${IMAGE_NAME}:${IMAGE_TAG}" + ''' | xargs -r docker rmi
                        docker images -q ''' + "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" + ''' | xargs -r docker rmi
                    '''
                    echo "Successfully cleaned up workspace"
                }
            }
        }
    }  // Close 'stages' block
}  // Close 'pipeline' block

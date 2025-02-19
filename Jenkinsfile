pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "jfrog:8082/docker-local"
        JFROG_URL = "http://jfrog:8081/artifactory"
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
                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/pytorch_model.bin \
                            -o models/${env.MODEL_NAME}/pytorch_model.bin

                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/config.json \
                            -o models/${env.MODEL_NAME}/config.json

                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
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
                    def modelFiles = sh(script: "ls -1 ${modelPath} | wc -l", returnStdout: true).trim()

                    if (modelFiles.toInteger() == 0) {
                        error("Error: Model directory is empty!")
                    }

                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_USER', passwordVariable: 'MINIO_PASS')]) {
                        sh """
                            /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS} --quiet

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
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh """
                        export DOCKER_HOST="unix:///var/run/docker.sock"
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

        stage('Tag and Push Image to JFrog') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASSWORD')]) {
                    script {
                        sh """
                            export DOCKER_HOST="unix:///var/run/docker.sock"
                            docker login -u \$JFROG_USER -p \$JFROG_PASSWORD ${REGISTRY}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        """
                        echo "Successfully pushed image to JFrog"
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    sh """
                        rm -rf models/${env.MODEL_NAME}
                        export DOCKER_HOST="unix:///var/run/docker.sock"
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

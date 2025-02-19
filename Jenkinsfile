pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"
        NEXUS_HTTP_PORT = "8081"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_HTTP_PORT}/repository/docker-hosted"
        NEXUS_URL = "http://${NEXUS_HOST}:${NEXUS_HTTP_PORT}"
        DOCKER_REPO_NAME = "docker-hosted"
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

       stage('Check/Create Nexus Docker Repository') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        // Write a temporary script to check if repo exists
                        writeFile file: 'check_repo.sh', text: '''
                            #!/bin/bash
                            curl -s -o /dev/null -w "%{http_code}" \
                                -u "$1:$2" \
                                "$3/service/rest/v1/repositories/$4"
                        '''
                        
                        sh 'chmod +x check_repo.sh'
                        
                        // Execute the script passing credentials as arguments
                        def repoExists = sh(
                            script: "./check_repo.sh '${NEXUS_USER}' '${NEXUS_PASSWORD}' '${NEXUS_URL}' '${DOCKER_REPO_NAME}'",
                            returnStdout: true
                        ).trim()
                        
                        // Clean up temporary script
                        sh 'rm check_repo.sh'
                        
                        if (repoExists != "200") {
                            echo "Docker repository '${DOCKER_REPO_NAME}' doesn't exist. Creating it..."
                            
                            // Write a temporary script to create repo
                            writeFile file: 'create_repo.sh', text: '''
                                #!/bin/bash
                                curl -X POST "$3/service/rest/v1/repositories/docker/hosted" \
                                -u "$1:$2" \
                                -H "Content-Type: application/json" \
                                -d '{
                                    "name": "'$4'",
                                    "online": true,
                                    "storage": {
                                        "blobStoreName": "default",
                                        "strictContentTypeValidation": true,
                                        "writePolicy": "ALLOW"
                                    },
                                    "docker": {
                                        "v1Enabled": true,
                                        "forceBasicAuth": true,
                                        "httpPort": '$5'
                                    }
                                }'
                            '''
                            
                            sh 'chmod +x create_repo.sh'
                            
                            // Execute the script passing credentials as arguments
                            sh "./create_repo.sh '${NEXUS_USER}' '${NEXUS_PASSWORD}' '${NEXUS_URL}' '${DOCKER_REPO_NAME}' '${NEXUS_DOCKER_PORT}'"
                            
                            // Clean up temporary script
                            sh 'rm create_repo.sh'
                            
                            echo "Docker repository '${DOCKER_REPO_NAME}' created successfully"
                        } else {
                            echo "Docker repository '${DOCKER_REPO_NAME}' already exists"
                        }
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

        stage('Tag and Push Image to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        sh """
                            export DOCKER_HOST="unix:///var/run/docker.sock"
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

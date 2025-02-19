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
                        mkdir -p ${env.MODEL_NAME}
                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/pytorch_model.bin \
                            -o ${env.MODEL_NAME}/pytorch_model.bin
                        
                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/config.json \
                            -o ${env.MODEL_NAME}/config.json
                        
                        curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${MODEL_REPO}/resolve/main/vocab.txt \
                            -o ${env.MODEL_NAME}/vocab.txt
                    """
                    echo "Successfully downloaded model: ${env.MODEL_NAME}"
                }
            }
        }

       stage('Upload Model to MinIO') {
            steps {
                script {
                    def modelPath = "${WORKSPACE}/models/bert-tiny"
                    def downloadedModelPath = "${WORKSPACE}/bert-tiny"
        
                    // Ensure the model directory exists
                    sh "mkdir -p ${modelPath}"
        
                    // Copy downloaded model files to the correct directory
                    sh "cp -r ${downloadedModelPath}/* ${modelPath}/"
        
                    // Debug: Check if the files exist
                    sh "ls -lah ${modelPath}"
        
                    if (fileExists(modelPath)) {
                        withCredentials([string(credentialsId: 'minio-secret-key', variable: 'MINIO_SECRET_KEY')]) {
                            withEnv(["MINIO_ALIAS=myminio", "MINIO_URL=http://minio:9000"]) {
                                sh """
                                /usr/local/bin/mc alias set ${MINIO_ALIAS} ${MINIO_URL} admin ${MINIO_SECRET_KEY} --quiet
                                /usr/local/bin/mc cp --recursive ${modelPath} myminio/models/
                                """
                            }
                        }
                    } else {
                        error("Error: Model directory is empty!")
                    }
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

        stage('Tag and Push Image to JFrog') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASSWORD')]) {
                    script {
                        sh """
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
                        rm -rf ${env.MODEL_NAME}
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

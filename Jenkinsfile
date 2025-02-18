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
        MODEL_REPO = "prajjwal1/bert-tiny"
    }

    stages {
        stage('Install Dependencies') {
            steps {
                script {
                    try {
                        sh '''
                            apt-get update
                            apt-get install -y wget curl
                        '''
                        echo "Successfully installed system dependencies"
                    } catch (Exception e) {
                        echo "Error installing dependencies: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to dependency installation failure.")
                    }
                }
            }
        }

        stage('Read Model Config') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        env.MODEL_NAME = modelConfig.model_name
                        echo "Successfully read model config. Model: ${env.MODEL_NAME}"
                    } catch (Exception e) {
                        echo "Error reading model config: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to config read failure.")
                    }
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        def modelName = modelConfig.model_name // Dynamically fetch model name from config

                        sh "mkdir -p ${modelName}"
                        sh """
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${modelName}/resolve/main/pytorch_model.bin \
                                -o ${modelName}/pytorch_model.bin
                            
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${modelName}/resolve/main/config.json \
                                -o ${modelName}/config.json
                            
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${modelName}/resolve/main/vocab.txt \
                                -o ${modelName}/vocab.txt
                        """
                        echo "Successfully downloaded ${modelName} model from Hugging Face"
                    } catch (Exception e) {
                        echo "Error fetching model from Hugging Face: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to model fetch failure.")
                    }
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_ACCESS_KEY', passwordVariable: 'MINIO_SECRET_KEY')]) {
                    script {
                        try {
                            // Use curl to download mc (MinIO client)
                            sh '''
                                curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
                                chmod +x mc
                                ./mc alias set myminio ${MINIO_URL} $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
                                ./mc mb myminio/${BUCKET_NAME} || true
                                ./mc cp -r ${modelName} myminio/${BUCKET_NAME}/
                                rm mc
                            '''
                            echo "Successfully uploaded model to MinIO"
                        } catch (Exception e) {
                            echo "Error uploading model to MinIO: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to model upload failure.")
                        }
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        sh """
                            docker build \
                                --build-arg MINIO_URL=${MINIO_URL} \
                                --build-arg BUCKET_NAME=${BUCKET_NAME} \
                                --build-arg MODEL_NAME=${env.MODEL_NAME} \
                                -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        """
                        echo "Successfully built Docker image"
                    } catch (Exception e) {
                        echo "Error building Docker image: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to Docker image build failure.")
                    }
                }
            }
        }

        stage('Tag and Push Image to JFrog') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASSWORD')]) {
                    script {
                        try {
                            sh """
                                docker login -u $JFROG_USER -p $JFROG_PASSWORD ${REGISTRY}
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            """
                            echo "Successfully pushed image to JFrog"
                        } catch (Exception e) {
                            echo "Error tagging and pushing image to JFrog: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to JFrog image push failure.")
                        }
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    try {
                        sh """
                            rm -rf ${modelName}
                            docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                            docker rmi ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                        """
                        echo "Successfully cleaned up workspace"
                    } catch (Exception e) {
                        echo "Warning: Cleanup encountered issues: ${e.message}"
                    }
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

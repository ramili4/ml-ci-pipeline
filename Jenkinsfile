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
        MODEL_REPO = "google/bert_uncased_L-2_H-128_A-2"  // Smallest model
    }

    stages {
        stage('Read Model Config') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        env.MODEL_NAME = modelConfig.model_name ?: "bert-tiny"
                        echo "Using model: ${env.MODEL_NAME}"
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
                        sh """
                            mkdir -p ${MODEL_NAME}
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${MODEL_REPO}/resolve/main/pytorch_model.bin \
                                -o ${MODEL_NAME}/pytorch_model.bin
                            
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${MODEL_REPO}/resolve/main/config.json \
                                -o ${MODEL_NAME}/config.json
                            
                            curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
                                -L https://huggingface.co/${MODEL_REPO}/resolve/main/vocab.txt \
                                -o ${MODEL_NAME}/vocab.txt
                        """
                        echo "Successfully downloaded model: ${MODEL_NAME}"
                    } catch (Exception e) {
                        echo "Error fetching model: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to model fetch failure.")
                    }
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                script {
                    def mcPath = '/usr/bin/mc'

                    if (!fileExists(mcPath)) {
                        error("Error: mc binary not found at ${mcPath}")
                    }

                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_ACCESS_KEY', passwordVariable: 'MINIO_SECRET_KEY')]) {
                        sh """
                            ${mcPath} alias set myminio ${MINIO_URL} $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
                            ${mcPath} cp -r ${MODEL_NAME} myminio/${BUCKET_NAME}/
                        """
                        echo "Model successfully uploaded to MinIO."
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
                                --build-arg MODEL_NAME=${MODEL_NAME} \
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
                            echo "Error pushing image to JFrog: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to image push failure.")
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
                            rm -rf ${MODEL_NAME}
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

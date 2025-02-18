pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "jfrog:8082/docker-local"
        JFROG_URL = "http://jfrog:8081/artifactory"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token') // Assuming Hugging Face token is in Jenkins credentials
    }

    stages {
        stage('Clone Repository') {
            steps {
                script {
                    // Check if the directory exists and clean it up before cloning
                    if (fileExists('/tmp/ml-ci-pipeline')) {
                        echo 'Directory /tmp/ml-ci-pipeline already exists. Cleaning up before cloning.'
                        try {
                            sh 'rm -rf /tmp/ml-ci-pipeline'
                        } catch (Exception e) {
                            echo "Error cleaning up directory: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to cleanup failure.")
                        }
                    }

                    try {
                        // Clone the repository
                        sh 'git clone https://github.com/ramili4/ml-ci-pipeline.git /tmp/ml-ci-pipeline'
                    } catch (Exception e) {
                        echo "Error cloning repository: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to repository clone failure.")
                    }
                }
            }
        }

        stage('Read Model Config') {
            steps {
                script {
                    try {
                        // Parse the model-config.yaml to get the model name and repo
                        def modelConfig = readYaml file: '/tmp/ml-ci-pipeline/model-config.yaml'
                        env.MODEL_NAME = modelConfig.model_name
                        env.HUGGINGFACE_REPO = modelConfig.huggingface_repo
                    } catch (Exception e) {
                        echo "Error reading model config: ${e.message}"
                        currentBuild.result = 'FAILURE'
                        error("Stopping pipeline due to config file read failure.")
                    }
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    try {
                        // Create directory for model
                        sh 'mkdir -p /tmp/ml-ci-pipeline/bert-sentiment'

                        // Fetch model using curl
                        sh 'curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" -L https://huggingface.co/nlptown/bert-base-multilingual-uncased-sentiment/resolve/main/pytorch_model.bin -o /tmp/ml-ci-pipeline/bert-sentiment/pytorch_model.bin'
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
                            sh """
                                apt update && apt install -y mc  # Install MinIO client
                                mc alias set myminio ${MINIO_URL} $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
                                mc mb myminio/${BUCKET_NAME} || true
                                mc cp -r /opt/ml-ci-pipeline/${MODEL_NAME} myminio/${BUCKET_NAME}/
                            """
                        } catch (Exception e) {
                            echo "Error uploading model to MinIO: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to MinIO upload failure.")
                        }
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        // Build Docker image with the specified base image and other settings
                        sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
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
                        } catch (Exception e) {
                            echo "Error tagging or pushing Docker image to JFrog: ${e.message}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to JFrog push failure.")
                        }
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
            echo "Pipeline failed!"
        }
    }
}

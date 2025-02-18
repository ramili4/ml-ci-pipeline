pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        MODEL_NAME = "huggingface-model"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "jfrog:8082/docker-local"
        JFROG_URL = "http://jfrog:8081/artifactory"
    }

    stages {
        stage('Clone Repository') {
            steps {
                script {
                    sh 'git clone https://huggingface.co/my-model /opt/ml-models-wsl'
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_ACCESS_KEY', passwordVariable: 'MINIO_SECRET_KEY')]) {
                    script {
                        sh """
                            apt update && apt install -y mc  # Install MinIO client
                            mc alias set myminio ${MINIO_URL} $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
                            mc mb myminio/${BUCKET_NAME} || true
                            mc cp -r /opt/ml-models-wsl/${MODEL_NAME} myminio/${BUCKET_NAME}/
                        """
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }

        stage('Tag and Push Image to JFrog') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASSWORD')]) {
                    script {
                        sh """
                            docker login -u $JFROG_USER -p $JFROG_PASSWORD ${REGISTRY}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        """
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

pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "jfrog:8082/docker-local"
        JFROG_URL = "http://jfrog:8081/artifactory"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-api-token') // Assuming Hugging Face token is in Jenkins credentials
    }

    stages {
        stage('Clone Repository') {
            steps {
                script {
                    // Clone the repository containing the Jenkinsfile and model-config.yaml
                    sh 'git clone https://github.com/ramili4/ml-ci-pipeline.git /opt/ml-ci-pipeline'
                }
            }
        }

        stage('Read Model Config') {
            steps {
                script {
                    // Parse the model-config.yaml to get the model name and repo
                    def modelConfig = readYaml file: '/opt/ml-ci-pipeline/model-config.yaml'
                    env.MODEL_NAME = modelConfig.model_name
                    env.HUGGINGFACE_REPO = modelConfig.huggingface_repo
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    // Use Hugging Face API to fetch the model using the API token
                    sh """
                        mkdir -p /opt/ml-ci-pipeline/${env.MODEL_NAME}
                        wget --header="Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                             "https://huggingface.co/${env.HUGGINGFACE_REPO}/resolve/main/pytorch_model.bin" -O /opt/ml-ci-pipeline/${env.MODEL_NAME}/pytorch_model.bin
                    """
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
                            mc cp -r /opt/ml-ci-pipeline/${MODEL_NAME} myminio/${BUCKET_NAME}/
                        """
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Build Docker image with the specified base image and other settings
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

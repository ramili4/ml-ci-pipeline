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
                    try {
                        // Check if the directory exists
                        if (fileExists('/tmp/ml-ci-pipeline')) {
                            echo 'Directory /tmp/ml-ci-pipeline already exists. Cleaning up before cloning.'
                            // Clean the existing directory
                            sh 'rm -rf /tmp/ml-ci-pipeline'
                        }
                        
                        // Clone the repository
                        echo 'Cloning repository...'
                        sh 'git clone https://github.com/ramili4/ml-ci-pipeline.git /tmp/ml-ci-pipeline'
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error "Failed to clone the repository: ${e.message}"
                    }
                }
            }
        }

        stage('Read Model Config') {
            steps {
                script {
                    try {
                        // Parse the model-config.yaml to get the model name and repo
                        echo 'Reading model config...'
                        def modelConfig = readYaml file: '/tmp/ml-ci-pipeline/model-config.yaml'
                        env.MODEL_NAME = modelConfig.model_name
                        env.HUGGINGFACE_REPO = modelConfig.huggingface_repo
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error "Failed to read model config: ${e.message}"
                    }
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    try {
                        // Create directory for model
                        echo 'Creating directory for model...'
                        sh 'mkdir -p /tmp/ml-ci-pipeline/bert-sentiment'

                        // Fetch model using curl
                        echo 'Fetching model from Hugging Face...'
                        sh 'curl -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" -L https://huggingface.co/nlptown/bert-base-multilingual-uncased-sentiment/resolve/main/pytorch_model.bin -o /tmp/ml-ci-pipeline/bert-sentiment/pytorch_model.bin'
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error "Failed to fetch model from Hugging Face: ${e.message}"
                    }
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_ACCESS_KEY', passwordVariable: 'MINIO_SECRET_KEY')]) {
                    script {
                        try {
                            echo 'Installing MinIO client and uploading model...'
                            sh """
                                apt update && apt install -y mc  # Install MinIO client
                                mc alias set myminio ${MINIO_URL} $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
                                mc mb myminio/${BUCKET_NAME} || true
                                mc cp -r /tmp/ml-ci-pipeline/${MODEL_NAME} myminio/${BUCKET_NAME}/
                            """
                        } catch (Exception e) {
                            currentBuild.result = 'FAILURE'
                            error "Failed to upload model to MinIO: ${e.message}"
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
                        echo 'Building Docker image...'
                        sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error "Failed to build Docker image: ${e.message}"
                    }
                }
            }
        }

        stage('Tag and Push Image to JFrog') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASSWORD')]) {
                    script {
                        try {
                            echo 'Tagging and pushing Docker image to JFrog...'
                            sh """
                                docker login -u $JFROG_USER -p $JFROG_PASSWORD ${REGISTRY}
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            """
                        } catch (Exception e) {
                            currentBuild.result = 'FAILURE'
                            error "Failed to tag and push Docker image to JFrog: ${e.message}"
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

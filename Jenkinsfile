pipeline {
    agent any

    environment {
        HUGGINGFACE_TOKEN = credentials('huggingface-token')  // Stored in Jenkins credentials
        MODEL_DIR = '~/mock-storage/minio/models/bert-sentiment/1.0.0'
        MOCK_DOCKER_DIR = '~/mock-storage/jfrog/docker-images'
        VENV_DIR = '~/mock-storage/ml-pipeline/venv'
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Validate Model Config') {
            steps {
                script {
                    def config = readYaml file: 'model-config.yaml'
                    echo "Config validation successful"
                }
            }
        }

        stage('Setup Mock Storage') {
            steps {
                script {
                    echo "Creating mock directories..."
                    sh "mkdir -p ${MODEL_DIR}"
                    sh "mkdir -p ${MOCK_DOCKER_DIR}"
                    sh "mkdir -p ${VENV_DIR}"
                }
            }
        }

        stage('Setup Python Virtual Environment') {
            steps {
                script {
                    echo "Setting up Python virtual environment..."
                    sh "python3 -m venv ${VENV_DIR}"
                    sh ". ${VENV_DIR}/bin/activate && pip install --upgrade pip"
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo "Installing Hugging Face CLI..."
                    sh ". ${VENV_DIR}/bin/activate && pip install huggingface_hub"
                }
            }
        }

        stage('Download and Store Model (Simulated MinIO)') {
            steps {
                script {
                    echo "Downloading model using Hugging Face CLI..."
                    sh ". ${VENV_DIR}/bin/activate && huggingface-cli download nlptown/bert-base-multilingual-uncased-sentiment --token ${HUGGINGFACE_TOKEN} --local-dir ${MODEL_DIR}"

                    echo "[DRY RUN] Simulating MinIO upload..."
                    sh "ls -l ${MODEL_DIR}"  // List files to confirm
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image..."
                    sh "docker build -t my-docker-image:${BUILD_NUMBER} ."
                }
            }
        }

        stage('Push to JFrog (Simulated)') {
            steps {
                script {
                    echo "[DRY RUN] Would push to JFrog: my-docker-image:${BUILD_NUMBER}"
                    sh "cp -r ./docker-build ${MOCK_DOCKER_DIR}/"
                    sh "ls -l ${MOCK_DOCKER_DIR}"  // Verify the mock push
                }
            }
        }
    }
}

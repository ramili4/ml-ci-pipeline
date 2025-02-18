pipeline {
    agent any

    environment {
        WORKSPACE_DIR = "${WORKSPACE}/mock-storage"
        MODEL_DIR = "${WORKSPACE_DIR}/minio/models/bert-sentiment/1.0.0"
        MOCK_DOCKER_DIR = "${WORKSPACE_DIR}/jfrog/docker-images"
        VENV_DIR = "${WORKSPACE_DIR}/ml-pipeline/venv"
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
                    sh "sudo mkdir -p ${MODEL_DIR}"
                    sh "sudo mkdir -p ${MOCK_DOCKER_DIR}"
                    sh "sudo mkdir -p ${VENV_DIR}"
                }
            }
        }

        stage('Setup Python Virtual Environment') {
            steps {
                script {
                    echo "Setting up Python virtual environment..."
                    sh "sudo python3 -m venv ${VENV_DIR}"
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

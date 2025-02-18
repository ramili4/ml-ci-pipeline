pipeline {
    agent any

    environment {
        HUGGINGFACE_TOKEN = credentials('huggingface-token') 
        MODEL_DIR = '/opt/ml-models/bert-sentiment/1.0.0'
    }

    stages {
        stage('Declarative: Checkout SCM') {
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

        stage('Initialize Local Storage') {
            steps {
                script {
                    echo "[DRY RUN] Would create storage directory: ${MODEL_DIR}"
                    // Uncomment to actually create the directory
                    // sh "mkdir -p ${MODEL_DIR}"
                }
            }
        }

        stage('Set Up Python Virtual Environment') {
            steps {
                script {
                    // Create and activate the Python virtual environment
                    echo "Setting up Python virtual environment..."
                    sh 'python3 -m venv /opt/ml-pipeline/venv'
                    sh '. /opt/ml-pipeline/venv/bin/activate && pip install --upgrade pip'
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    // Install Hugging Face CLI in the virtual environment
                    echo "Installing Hugging Face CLI..."
                    sh '. /opt/ml-pipeline/venv/bin/activate && pip install huggingface_hub'
                }
            }
        }

        stage('Download and Store Model') {
            steps {
                script {
                    // Download the model using Hugging Face CLI inside the venv
                    echo "Downloading model..."
                    sh '. /opt/ml-pipeline/venv/bin/activate && huggingface-cli download nlptown/bert-base-multilingual-uncased-sentiment --token ${HUGGINGFACE_TOKEN} --local-dir ${MODEL_DIR}'
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

        stage('Push to JFrog Artifactory') {
            steps {
                script {
                    echo "Pushing image to JFrog..."
                    withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', usernameVariable: 'JFROG_USER', passwordVariable: 'JFROG_PASS')]) {
                        sh "docker login -u $JFROG_USER -p $JFROG_PASS my-artifactory.com"
                        sh "docker push my-artifactory.com/my-docker-image:${BUILD_NUMBER}"
                    }
                }
            }
        }

        stage('Declarative: Post Actions') {
            steps {
                cleanWs() // Clean workspace after build
            }
        }
    }

    post {
        failure {
            echo 'Pipeline failed! Check the logs for details.'
        }
    }
}

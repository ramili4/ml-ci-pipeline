pipeline {
    agent any

    environment {
        // Define your credentials and model directory paths as environment variables
        HUGGINGFACE_TOKEN = credentials('huggingface-token')  // Make sure to store the token in Jenkins credentials
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
                    // Assuming you have a model config file that needs validation
                    def config = readYaml file: 'model-config.yaml'
                    echo "Config validation successful"
                }
            }
        }

        stage('Initialize Local Storage') {
            steps {
                script {
                    // Create directory for storing model, dry-run for now
                    echo "[DRY RUN] Would create storage directory: ${MODEL_DIR}"
                    // Uncomment this line when ready to actually create the directory
                    // sh "mkdir -p ${MODEL_DIR}"
                }
            }
        }

        stage('Install Hugging Face CLI') {
            steps {
                script {
                    // Install Hugging Face CLI tool
                    echo "Installing Hugging Face CLI..."
                    sh 'pip install --upgrade huggingface_hub'
                }
            }
        }

        stage('Download and Store Model') {
            steps {
                script {
                    // Download model using Hugging Face CLI
                    echo "Downloading model..."
                    sh "huggingface-cli download nlptown/bert-base-multilingual-uncased-sentiment --token ${HUGGINGFACE_TOKEN} --local-dir ${MODEL_DIR}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Build Docker image with the model
                    echo "Building Docker image..."
                    sh "docker build -t my-docker-image:${BUILD_NUMBER} ."
                }
            }
        }

        stage('Push to JFrog Artifactory') {
            steps {
                script {
                    // Push the Docker image to JFrog Artifactory
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

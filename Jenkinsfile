pipeline {
    agent any

    environment {
        MINIO_URL = "http://localhost:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "localhost:8082/artifactory/docker-local"
        JFROG_URL = "http://localhost:8081/artifactory"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        WORKSPACE_DIR = "${WORKSPACE}"
    }

    stage('Setup Environment') {
    steps {
        script {
            try {
                sh '''
                    # Ensure the apt lists directory exists and fix permissions
                    sudo mkdir -p /var/lib/apt/lists/partial
                    sudo chmod -R 755 /var/lib/apt/lists

                    # Fix any locked apt processes before updating
                    sudo rm -rf /var/lib/apt/lists/lock
                    sudo rm -rf /var/cache/apt/archives/lock
                    sudo rm -rf /var/lib/dpkg/lock*

                    # Update package lists
                    sudo apt-get update || sudo apt-get update --fix-missing

                    # Install Python and pip
                    sudo apt-get install -y python3 python3-pip

                    # Ensure pip3 is available
                    if ! command -v pip3 &> /dev/null; then
                        echo "pip3 not found, installing..."
                        sudo apt-get install -y python3-pip
                    fi

                    # Install Python dependencies
                    pip3 install --user pyyaml requests

                    # Verify installation
                    python3 --version
                    pip3 --version
                '''
                echo "Environment setup completed successfully"
            } catch (Throwable e) {
                echo "Error during environment setup: ${e.message}"
                error("Failed to setup environment. Stopping pipeline.")
            }
        }
    }
}


        stage('Checkout') {
            steps {
                script {
                    try {
                        checkout scm
                        echo "Repository checkout successful"
                    } catch (Throwable e) {
                        echo "Error during repository checkout: ${e.message}"
                        error("Failed to checkout repository. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Validate Config') {
            steps {
                script {
                    try {
                        if (!fileExists('model-config.yaml')) {
                            error("model-config.yaml not found in repository")
                        }

                        def modelConfig = readYaml file: 'model-config.yaml'
                        def requiredFields = ['model_name', 'huggingface_repo', 'model_files']
                        
                        requiredFields.each { field ->
                            if (!modelConfig[field]) {
                                error("Missing required field in config: ${field}")
                            }
                        }

                        env.MODEL_NAME = modelConfig.model_name
                        env.MODEL_REPO = modelConfig.huggingface_repo
                        env.MODEL_FILES = modelConfig.model_files.join(' ')

                        echo "Config validation successful"
                    } catch (Throwable e) {
                        echo "Error during config validation: ${e.message}"
                        error("Config validation failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Check Model Directory') {
            steps {
                script {
                    try {
                        def modelDir = "${WORKSPACE}/models/${env.MODEL_NAME}"
                        if (!fileExists(modelDir)) {
                            sh "mkdir -p ${modelDir}"
                            echo "Model directory created."
                        } else {
                            def modelDirEmpty = sh(script: "ls -A ${modelDir} | wc -l", returnStdout: true).trim() == "0"
                            if (!modelDirEmpty) {
                                sh "rm -rf ${modelDir}/*"
                                echo "Model directory cleaned."
                            }
                        }
                    } catch (Throwable e) {
                        echo "Error handling model directory: ${e.message}"
                        error("Failed to prepare model directory. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Fetch Model from Hugging Face') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        def modelDir = "${WORKSPACE}/models/${env.MODEL_NAME}"
                        def successCount = 0
                        def totalFiles = modelConfig.model_files.size()

                        modelConfig.model_files.each { file ->
                            def status = sh(script: """
                                curl -f -s -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                                    -L https://huggingface.co/${env.MODEL_REPO}/resolve/main/${file} \
                                    -o ${modelDir}/${file}
                            """, returnStatus: true)

                            if (status == 0) {
                                successCount++
                                echo "Successfully downloaded ${file}"
                            } else {
                                echo "Failed to download ${file}"
                            }
                        }

                        if (successCount != totalFiles) {
                            error("Some model files failed to download. Downloaded: ${successCount}/${totalFiles}")
                        }
                    } catch (Throwable e) {
                        echo "Error downloading model files: ${e.message}"
                        error("Model download failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Setup MinIO Client') {
            steps {
                script {
                    try {
                        withCredentials([usernamePassword(credentialsId: 'minio-credentials', 
                                       usernameVariable: 'MINIO_ACCESS_KEY', 
                                       passwordVariable: 'MINIO_SECRET_KEY')]) {
                            sh '''
                                wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O mc
                                chmod +x mc
                                ./mc alias set myminio ${MINIO_URL} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}
                            '''
                        }
                        echo "MinIO client setup successful"
                    } catch (Throwable e) {
                        echo "Error setting up MinIO client: ${e.message}"
                        error("MinIO setup failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Upload Model to MinIO') {
            steps {
                script {
                    try {
                        withCredentials([usernamePassword(credentialsId: 'minio-credentials', 
                                       usernameVariable: 'MINIO_ACCESS_KEY', 
                                       passwordVariable: 'MINIO_SECRET_KEY')]) {
                            sh '''
                                ./mc mb myminio/${BUCKET_NAME} || true
                                ./mc cp -r ${WORKSPACE}/models/${MODEL_NAME} myminio/${BUCKET_NAME}/
                            '''
                        }
                        echo "Model upload to MinIO successful"
                    } catch (Throwable e) {
                        echo "Error uploading to MinIO: ${e.message}"
                        error("MinIO upload failed. Stopping pipeline.")
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
                        echo "Docker image build successful"
                    } catch (Throwable e) {
                        echo "Error building Docker image: ${e.message}"
                        error("Docker build failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Push to JFrog Artifactory') {
            steps {
                script {
                    try {
                        withCredentials([usernamePassword(credentialsId: 'jfrog-credentials', 
                                       usernameVariable: 'JFROG_USER', 
                                       passwordVariable: 'JFROG_PASSWORD')]) {
                            sh """
                                docker login -u ${JFROG_USER} -p ${JFROG_PASSWORD} ${REGISTRY}
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            """
                        }
                        echo "Image push to JFrog successful"
                    } catch (Throwable e) {
                        echo "Error pushing to JFrog: ${e.message}"
                        error("JFrog push failed. Stopping pipeline.")
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed! Check the logs for details."
        }
    }
}

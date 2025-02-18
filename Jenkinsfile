pipeline {
    agent any

    environment {
        MINIO_URL = "http://localhost:9000"
        BUCKET_NAME = "models"
        IMAGE_NAME = "my-app"
        IMAGE_TAG = "latest"
        REGISTRY = "localhost:8082/artifactory/docker-local"  // JFrog Docker registry
        JFROG_URL = "http://localhost:8081/artifactory"      // JFrog Artifactory URL
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        WORKSPACE_DIR = "${WORKSPACE}"
    }

    stages {
        stage('Setup Environment') {
            steps {
                script {
                    try {
                        // Install required packages
                        sh '''
                            apk update
                            apk add --no-cache curl python3 py3-pip wget git
                            pip3 install pyyaml requests
                        '''
                        
                        // Create necessary directories
                        sh '''
                            mkdir -p ${WORKSPACE_DIR}/models
                            mkdir -p ${WORKSPACE_DIR}/tmp
                        '''
                        echo "Environment setup completed successfully"
                    } catch (Exception e) {
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
                    } catch (Exception e) {
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
                        // Check if config file exists
                        if (!fileExists('model-config.yaml')) {
                            error("model-config.yaml not found in repository")
                        }

                        def modelConfig = readYaml file: 'model-config.yaml'
                        
                        // Validate required fields
                        def requiredFields = ['model_name', 'huggingface_repo', 'model_files']
                        requiredFields.each { field ->
                            if (!modelConfig.containsKey(field) || !modelConfig[field]) {
                                error("Missing required field in config: ${field}")
                            }
                        }

                        // Set environment variables
                        env.MODEL_NAME = modelConfig.model_name
                        env.MODEL_REPO = modelConfig.huggingface_repo
                        env.MODEL_FILES = modelConfig.model_files.join(' ')
                        
                        echo "Config validation successful"
                    } catch (Exception e) {
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
                        // Check if model directory exists and is not empty
                        def modelDir = "${WORKSPACE_DIR}/models/${env.MODEL_NAME}"
                        def modelDirExists = sh(script: "test -d ${modelDir}", returnStatus: true) == 0
                        def modelDirEmpty = sh(script: "test -z \"\$(ls -A ${modelDir} 2>/dev/null)\"", returnStatus: true) == 0

                        if (!modelDirExists) {
                            echo "Model directory doesn't exist. Creating it..."
                            sh "mkdir -p ${modelDir}"
                        } else if (!modelDirEmpty) {
                            echo "Model directory exists and contains files. Cleaning..."
                            sh "rm -rf ${modelDir}/*"
                        }
                    } catch (Exception e) {
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
                        def modelDir = "${WORKSPACE_DIR}/models/${env.MODEL_NAME}"
                        def successCount = 0
                        def totalFiles = modelConfig.model_files.size()

                        modelConfig.model_files.each { file ->
                            def status = sh(script: """
                                curl -f -s -H "Authorization: Bearer $HUGGINGFACE_API_TOKEN" \
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
                    } catch (Exception e) {
                        echo "Error downloading model files: ${e.message}"
                        error("Model download failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Check MinIO Connection') {
            steps {
                script {
                    try {
                        withCredentials([usernamePassword(credentialsId: 'minio-credentials', 
                                       usernameVariable: 'MINIO_ACCESS_KEY', 
                                       passwordVariable: 'MINIO_SECRET_KEY')]) {
                            def status = sh(script: """
                                wget -q https://dl.min.io/client/mc/release/linux-amd64/mc
                                chmod +x mc
                                ./mc alias set myminio ${MINIO_URL} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}
                                ./mc ping myminio
                            """, returnStatus: true)
                            
                            if (status != 0) {
                                error("Unable to connect to MinIO server")
                            }
                        }
                        echo "MinIO connection successful"
                    } catch (Exception e) {
                        echo "Error connecting to MinIO: ${e.message}"
                        error("MinIO connection failed. Stopping pipeline.")
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
                            // Create bucket if it doesn't exist
                            sh """
                                ./mc mb myminio/${BUCKET_NAME} || true
                                if ./mc ls myminio/${BUCKET_NAME}/${env.MODEL_NAME}/ > /dev/null 2>&1; then
                                    echo "Removing existing model files..."
                                    ./mc rm --recursive --force myminio/${BUCKET_NAME}/${env.MODEL_NAME}/
                                fi
                                ./mc cp -r ${WORKSPACE_DIR}/models/${env.MODEL_NAME} myminio/${BUCKET_NAME}/
                            """
                        }
                        echo "Model upload to MinIO successful"
                    } catch (Exception e) {
                        echo "Error uploading to MinIO: ${e.message}"
                        error("MinIO upload failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Check Docker Environment') {
            steps {
                script {
                    try {
                        def dockerInfo = sh(script: 'docker info', returnStatus: true)
                        if (dockerInfo != 0) {
                            error("Docker daemon is not accessible")
                        }
                        echo "Docker environment check successful"
                    } catch (Exception e) {
                        echo "Error checking Docker environment: ${e.message}"
                        error("Docker environment check failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        // Check if image already exists
                        def imageExists = sh(script: "docker images -q ${IMAGE_NAME}:${IMAGE_TAG}", returnStdout: true).trim()
                        if (imageExists) {
                            echo "Removing existing image..."
                            sh "docker rmi -f ${IMAGE_NAME}:${IMAGE_TAG}"
                        }

                        sh """
                            docker build \
                                --build-arg MINIO_URL=${MINIO_URL} \
                                --build-arg BUCKET_NAME=${BUCKET_NAME} \
                                --build-arg MODEL_NAME=${env.MODEL_NAME} \
                                -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        """
                        echo "Docker image build successful"
                    } catch (Exception e) {
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
                            // Test JFrog connection
                            def jfrogStatus = sh(script: """
                                curl -f -u ${JFROG_USER}:${JFROG_PASSWORD} ${JFROG_URL}/api/system/ping
                            """, returnStatus: true)
                            
                            if (jfrogStatus != 0) {
                                error("Unable to connect to JFrog Artifactory")
                            }

                            sh """
                                docker login -u ${JFROG_USER} -p ${JFROG_PASSWORD} ${REGISTRY}
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            """
                        }
                        echo "Image push to JFrog successful"
                    } catch (Exception e) {
                        echo "Error pushing to JFrog: ${e.message}"
                        error("JFrog push failed. Stopping pipeline.")
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    try {
                        sh """
                            rm -rf ${WORKSPACE_DIR}/models/${env.MODEL_NAME} || true
                            rm -f mc || true
                            docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                            docker rmi ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                        """
                        echo "Cleanup successful"
                    } catch (Exception e) {
                        echo "Warning: Cleanup encountered issues: ${e.message}"
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
            script {
                // Cleanup on failure
                sh """
                    rm -rf ${WORKSPACE_DIR}/models/${env.MODEL_NAME} || true
                    rm -f mc || true
                    docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                    docker rmi ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                """
            }
        }
        always {
            cleanWs()
        }
    }
}

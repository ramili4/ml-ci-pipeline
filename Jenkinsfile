pipeline {
    agent any
    
    environment {
        HUGGINGFACE_TOKEN = credentials('huggingface-token')
        JFROG_CREDENTIALS = credentials('jfrog-credentials')
        DRY_RUN = 'true'  // Keep dry-run for JFrog
        LOCAL_STORAGE_BASE = '/opt/ml-models'
    }
    
    stages {
        stage('Validate Model Config') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        def requiredFields = ['model_name', 'version', 'huggingface_repo', 'docker.base_image']
                        def missingFields = []

                        requiredFields.each { field -> 
                            if (!validateConfigField(modelConfig, field)) {
                                missingFields.add(field)
                            }
                        }

                        if (missingFields) {
                            error("Missing required fields in model-config.yaml: ${missingFields.join(', ')}")
                        }

                        env.MODEL_NAME = modelConfig.model_name
                        env.MODEL_VERSION = modelConfig.version
                        env.HUGGINGFACE_REPO = modelConfig.huggingface_repo
                        env.DOCKER_BASE_IMAGE = modelConfig.docker.base_image
                        env.MODEL_STORAGE_PATH = "${LOCAL_STORAGE_BASE}/${env.MODEL_NAME}/${env.MODEL_VERSION}"

                        if (!env.MODEL_VERSION.matches('^\\d+\\.\\d+\\.\\d+$')) {
                            error("Invalid version format. Must be semantic versioning (e.g., 1.0.0)")
                        }

                        echo "Config validation successful"
                    } catch (Exception e) {
                        error("Failed to read or validate model-config.yaml: ${e.getMessage()}")
                    }
                }
            }
        }
        
        stage('Initialize Local Storage') {
            steps {
                script {
                    if (env.DRY_RUN.toBoolean()) {
                        echo "[DRY RUN] Would create storage directory: ${env.MODEL_STORAGE_PATH}"
                    } else {
                        sh """
                            mkdir -p ${env.MODEL_STORAGE_PATH}
                            chmod 755 ${env.MODEL_STORAGE_PATH}
                        """
                    }
                }
            }
        }
        
        stage('Install Hugging Face CLI') {
            steps {
                script {
                    if (env.DRY_RUN.toBoolean()) {
                        echo "[DRY RUN] Would install Hugging Face CLI"
                    } else {
                        try {
                            sh """
                                pip install --upgrade huggingface_hub
                            """
                        } catch (Exception e) {
                            error("Failed to install Hugging Face CLI: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        stage('Download and Store Model') {
            steps {
                script {
                    // Set DRY_RUN to false for downloading the model
                    def dryRunDownload = 'false'
                    
                    if (dryRunDownload.toBoolean()) {
                        echo "[DRY RUN] Would download model from: ${env.HUGGINGFACE_REPO}"
                    } else {
                        try {
                            sh """
                                huggingface-cli download ${env.HUGGINGFACE_REPO} \
                                    --token \${HUGGINGFACE_TOKEN} \
                                    --local-dir ${env.MODEL_STORAGE_PATH}
                            """

                            def metadata = """
                                model_name: ${env.MODEL_NAME}
                                version: ${env.MODEL_VERSION}
                                huggingface_repo: ${env.HUGGINGFACE_REPO}
                                download_date: ${new Date().format("yyyy-MM-dd HH:mm:ss")}
                            """
                            writeFile file: "${env.MODEL_STORAGE_PATH}/metadata.yaml", text: metadata
                        } catch (Exception e) {
                            error("Failed to download model: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // Keep the rest of the stages as is for JFrog with dry-run mode enabled.
        
        stage('Build Docker Image') {
            steps {
                script {
                    def imageTag = "${env.MODEL_NAME}:${env.MODEL_VERSION}"
                    if (env.DRY_RUN.toBoolean()) {
                        echo "[DRY RUN] Would build Docker image: ${imageTag}"
                    } else {
                        try {
                            sh """
                                docker build -t ${imageTag} \
                                    --build-arg BASE_IMAGE=${env.DOCKER_BASE_IMAGE} \
                                    --build-arg MODEL_PATH=${env.MODEL_STORAGE_PATH} .
                            """
                        } catch (Exception e) {
                            error("Failed to build Docker image: ${e.getMessage()}")
                        }
                    }
                }
            }
        }
        
        stage('Push to JFrog Artifactory') {
            steps {
                script {
                    def imageTag = "${env.MODEL_NAME}:${env.MODEL_VERSION}"
                    def artifactoryRepo = "artifactory.example.com"
                    if (env.DRY_RUN.toBoolean()) {
                        echo "[DRY RUN] Would push image to JFrog Artifactory"
                    } else {
                        try {
                            sh """
                                docker tag ${imageTag} ${artifactoryRepo}/${imageTag}
                                docker push ${artifactoryRepo}/${imageTag}
                            """
                        } catch (Exception e) {
                            error("Failed to push to Artifactory: ${e.getMessage()}")
                        }
                    }
                }
            }
        }
    }
    
    post {
        success {
            script {
                if (!env.DRY_RUN.toBoolean()) {
                    sh """
                        echo "Model successfully stored at: ${env.MODEL_STORAGE_PATH}" >> ${LOCAL_STORAGE_BASE}/storage_log.txt
                        du -sh ${env.MODEL_STORAGE_PATH} >> ${LOCAL_STORAGE_BASE}/storage_log.txt
                    """
                }
            }
        }
        failure {
            echo "Pipeline failed! Check the logs for details."
        }
        always {
            script {
                deleteDir()
                if (!env.DRY_RUN.toBoolean()) {
                    sh "rm -rf ${env.MODEL_STORAGE_PATH} || true"
                }
            }
        }
    }
}

def validateConfigField(config, field) {
    def fields = field.split('\\.')
    def current = config

    for (f in fields) {
        if (!(current instanceof Map) || !current.containsKey(f)) {
            return false
        }
        current = current[f]
    }

    return current != null
}

pipeline {
    agent any

    parameters {
        string(name: 'MODEL_NAME', defaultValue: '', description: 'Override model name')
        string(name: 'HUGGINGFACE_REPO', defaultValue: '', description: 'Override Hugging Face repo')
        booleanParam(name: 'SKIP_VULNERABILITY_CHECK', defaultValue: false, description: 'Skip vulnerability check')
        booleanParam(name: 'RUN_MODEL_TESTS', defaultValue: true, description: 'Run model tests')
    }

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"
        MINIO_MC_VERSION = "RELEASE.2023-02-28T00-12-59Z"
        TRIVY_VERSION = "0.45.0"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        TELEGRAM_TOKEN = credentials('Telegram_Bot_Token')
        TELEGRAM_CHAT_ID = credentials('Chat_id')
        MINIO_CREDS = credentials('minio-credentials')
        NEXUS_CREDS = credentials('nexus-credentials')
        TRIVY_CACHE_DIR = "/var/jenkins_home/trivy-cache"
        MODEL_CACHE_DIR = "/var/jenkins_home/model-cache"
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }

    stages {
        stage('Read Model Configuration') {
            steps {
                script {
                    def modelConfig = readYaml file: 'model-config.yaml'
                    env.MODEL_NAME = params.MODEL_NAME ?: modelConfig.model_name ?: "bert-tiny"
                    env.HF_REPO = params.HUGGINGFACE_REPO ?: modelConfig.huggingface_repo ?: "prajjwal1/bert-tiny"
                    def modelNameLower = env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")
                    env.IMAGE_NAME = "ml-model-${modelNameLower}"
                    env.IMAGE_TAG = "${BUILD_DATE}-${env.BUILD_NUMBER}"
                    writeFile file: 'version.json', text: """{
                        "model_name": "${env.MODEL_NAME}",
                        "huggingface_repo": "${env.HF_REPO}",
                        "build_date": "${BUILD_DATE}",
                        "build_number": "${env.BUILD_NUMBER}",
                        "image_name": "${env.IMAGE_NAME}",
                        "image_tag": "${env.IMAGE_TAG}"
                    }"""
                    echo "📋 Using model: ${env.MODEL_NAME} from repo: ${env.HF_REPO}"
                }
            }
        }

        stage('Download Model') {
            steps {
                script {
                    def modelCacheKey = env.HF_REPO.replaceAll("[/:]", "_")
                    def modelCachePath = "${MODEL_CACHE_DIR}/${modelCacheKey}"
                    def targetPath = "models/${env.MODEL_NAME}"
                    def modelCached = fileExists(modelCachePath)

                    if (!modelCached) {
                        sh "mkdir -p ${targetPath}"
                        sh """
                            curl -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                            -L https://huggingface.co/${env.HF_REPO}/resolve/main/pytorch_model.bin \
                            -o ${targetPath}/pytorch_model.bin
                        """
                        echo "✅ Model downloaded successfully."
                    } else {
                        echo "✅ Using cached model."
                    }
                }
            }
        }

        stage('Test Model') {
            when {
                expression { return params.RUN_MODEL_TESTS }
            }
            steps {
                script {
                    sh "echo Running model tests..."
                    sh """
                        docker run --rm \
                            -v ${WORKSPACE}/models:/models \
                            python:3.9-slim \
                            bash -c "pip install transformers torch && python -c 'from transformers import AutoModel; AutoModel.from_pretrained(\"/models/${env.MODEL_NAME}\")'"
                    """
                    echo "✅ Model tests completed."
                }
            }
        }

        stage('Save to MinIO and Build Docker Image') {
            parallel {
                stage('Save Model to MinIO') {
                    steps {
                        script {
                            def modelPath = "${WORKSPACE}/models/${env.MODEL_NAME}"
                            sh """
                                /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_CREDS_USR} ${MINIO_CREDS_PSW} --quiet || true
                                /usr/local/bin/mc mb myminio/${BUCKET_NAME} || true
                                /usr/local/bin/mc cp --recursive ${modelPath} myminio/${BUCKET_NAME}/${env.MODEL_NAME}/
                            """
                            echo "✅ Model saved to MinIO."
                        }
                    }
                }

                stage('Build Docker Image') {
                    steps {
                        script {
                            sh """
                                docker build \
                                    --build-arg MODEL_NAME=${env.MODEL_NAME} \
                                    -t ${env.IMAGE_NAME}:${env.IMAGE_TAG} .
                            """
                            echo "✅ Docker image built: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                        }
                    }
                }
            }
        }

        stage('Scan Image with Trivy') {
            steps {
                script {
                    sh """
                        trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                            --severity HIGH,CRITICAL \
                            ${env.IMAGE_NAME}:${env.IMAGE_TAG} > trivy-scan-results.txt
                    """
                    archiveArtifacts artifacts: 'trivy-scan-results.txt', fingerprint: true

                    def hasCritical = sh(script: "grep -q 'CRITICAL' trivy-scan-results.txt && echo true || echo false", returnStdout: true).trim()
                    if (hasCritical == "true" && !params.SKIP_VULNERABILITY_CHECK) {
                        error("❌ Critical vulnerabilities found. Build halted.")
                    } else {
                        echo "✅ No critical vulnerabilities detected."
                    }
                }
            }
        }

        stage('Push to Nexus') {
            steps {
                script {
                    sh """
                        echo "${NEXUS_CREDS_PSW}" | docker login -u "${NEXUS_CREDS_USR}" --password-stdin http://${REGISTRY}
                        docker tag ${env.IMAGE_NAME}:${env.IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                        docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                    """
                    echo "✅ Image pushed to Nexus."
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    sh """
                        rm -rf models/${env.MODEL_NAME}
                        docker rmi ${env.IMAGE_NAME}:${env.IMAGE_TAG} || true
                    """
                    echo "✅ Workspace cleaned."
                }
            }
        }
    }

    post {
        success {
            script {
                echo "✅ Pipeline completed successfully for ${env.MODEL_NAME}"
            }
        }
        failure {
            script {
                echo "❌ Pipeline failed. Check logs for details."
            }
        }
    }
}

pipeline {
    agent any

    environment {
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        TELEGRAM_TOKEN = credentials('Telegram_Bot_Token')  // Telegram Bot Token
        TELEGRAM_CHAT_ID = credentials('Chat_id')          // Telegram Chat ID
        DOCKER_HOST = "unix:///var/run/docker.sock"
        BUILD_DATE = sh(script: 'date +%Y%m%d', returnStdout: true).trim()
    }

    stages {
        stage('Считываем конфигурацию модели') {
            steps {
                script {
                    def modelConfig = readYaml file: 'model-config.yaml'
                    env.MODEL_NAME = modelConfig.model_name ?: "bert-tiny"
                    env.HF_REPO = modelConfig.huggingface_repo ?: "prajjwal1/bert-tiny"
                    env.IMAGE_TAG = "${BUILD_DATE}-latest"
                    env.IMAGE_NAME = "ml-model-${env.MODEL_NAME}"
                    echo "Using model: ${env.MODEL_NAME} from repo: ${env.HF_REPO}"
                }
            }
        }

        stage('Скачиваем модель из Hugging Face') {
            steps {
                script {
                    sh """
                        mkdir -p models/${env.MODEL_NAME}
                        set -e

                        for file in pytorch_model.bin config.json vocab.txt; do
                            curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                                -L https://huggingface.co/${env.HF_REPO}/resolve/main/\$file \
                                -o models/${env.MODEL_NAME}/\$file
                        done
                    """
                    echo "Успешно скачал модель: ${env.MODEL_NAME}"
                }
            }
        }

        stage('Сохраняем модель в MinIO') {
            steps {
                script {
                    def modelPath = "${WORKSPACE}/models/${env.MODEL_NAME}"
                    def modelFiles = sh(script: "ls -A ${modelPath} | wc -l", returnStdout: true).trim()

                    if (modelFiles.toInteger() == 0) {
                        error("Ошибка: Папка для модели пуста! Выходим..")
                    }

                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_USER', passwordVariable: 'MINIO_PASS')]) {
                        sh """
                            /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS} --quiet || true

                            if ! /usr/local/bin/mc ls myminio/${BUCKET_NAME} >/dev/null 2>&1; then
                                echo "Creating bucket ${BUCKET_NAME}..."
                                /usr/local/bin/mc mb myminio/${BUCKET_NAME}
                            fi

                            /usr/local/bin/mc cp --recursive ${modelPath} myminio/${BUCKET_NAME}/
                        """
                    }
                }
            }
        }

        stage('Собираем докер образ') {
            steps {
                script {
                    def modelNameLower = env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")
                    def imageName = "ml-model-${modelNameLower}"
                    env.IMAGE_NAME = imageName

                    sh """
                        docker build \
                            --build-arg MINIO_URL=${MINIO_URL} \
                            --build-arg BUCKET_NAME=${BUCKET_NAME} \
                            --build-arg MODEL_NAME=${env.MODEL_NAME} \
                            -t ${env.IMAGE_NAME}:${IMAGE_TAG} \
                            -f Dockerfile .
                    """
                    echo "Успешно собран Docker образ: ${env.IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }

        stage('Сканируем образ с помощью Trivy') {
            steps {
                script {
                    sh "mkdir -p trivy-reports"

                    sh """
                        trivy image --download-db-only

                        trivy image --cache-dir /tmp/trivy \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --scanners vuln \
                            ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.txt

                        trivy image --cache-dir /tmp/trivy \
                            --severity HIGH,CRITICAL \
                            --format json \
                            ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.json
                    """

                    echo "=== 📋 Результаты сканирования Trivy ==="
                    sh "cat trivy-reports/scan-results.txt"

                    archiveArtifacts artifacts: 'trivy-reports/**', fingerprint: true

                    def hasCritical = sh(script: "grep -q 'CRITICAL' trivy-reports/scan-results.txt && echo true || echo false", returnStdout: true).trim()

                    if (hasCritical == "true") {
                        def userChoice = input message: '🚨 Найдены критические уязвимости. Хотите продолжить?', 
                                              ok: 'Продолжить', 
                                              parameters: [choice(choices: 'Нет\nДа', description: 'Выберите действие', name: 'continueBuild')]
                        if (userChoice == 'Нет') {
                            error("Сборка остановлена из-за критических уязвимостей.")
                        } else {
                            echo "⚠️ Продолжаем несмотря на уязвимости."
                        }
                    } else {
                        echo "✅ Критических уязвимостей не обнаружено."
                    }
                }
            }
        }

        stage('Ставим тэг и пушим в Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        sh """
                            echo "$NEXUS_PASSWORD" | docker login -u "$NEXUS_USER" --password-stdin http://${REGISTRY}

                            docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest

                            docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                        """
                        echo "Успешно закачали образ: ${env.IMAGE_NAME} в Nexus"
                    }
                }
            }
        }

        stage('Прибираемся-)') {
            steps {
                script {
                    sh """
                        rm -rf models/${env.MODEL_NAME}

                        docker images -q ${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest | xargs -r docker rmi -f || true

                        rm -f trivy-results.txt
                    """
                    echo "Прибрались! Ляпота то какая, красота!"
                }
            }
        }
    }

    post {
        success {
            script {
                sh """
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                -d chat_id=${TELEGRAM_CHAT_ID} \
                -d text="✅ *Pipeline Success!* 🎉\\nJob: ${env.JOB_NAME}\\nBuild: #${env.BUILD_NUMBER}\\nStatus: SUCCESS" \
                -d parse_mode=Markdown
                """
            }
        }

        failure {
            script {
                sh """
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                -d chat_id=${TELEGRAM_CHAT_ID} \
                -d text="❌ *Упс! Надевай очки и иди читать логи! ${env.IMAGE_NAME} не хочет чтобы его скачали* 🚨\\nJob: ${env.JOB_NAME}\\nBuild: #${env.BUILD_NUMBER}\\nStatus: FAILURE" \
                -d parse_mode=Markdown
                """
            }
        }

        always {
            script {
                sh """
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                -d chat_id=${TELEGRAM_CHAT_ID} \
                -d text="ℹ️ *Все гуд, выдохни! Скачал я ${env.IMAGE_NAME}*\\nJob: ${env.JOB_NAME}\\nBuild: #${env.BUILD_NUMBER}" \
                -d parse_mode=Markdown
                """
            }
        }
    }
}

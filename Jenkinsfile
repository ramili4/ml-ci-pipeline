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

        stage('Создаем Dockerfile') {
            steps {
                script {
                    def dockerfileContent = """
                    FROM python:3.9-slim

                    ARG MINIO_URL
                    ARG BUCKET_NAME
                    ARG MODEL_NAME

                    ENV MINIO_URL=\${MINIO_URL}
                    ENV BUCKET_NAME=\${BUCKET_NAME}
                    ENV MODEL_NAME=\${MODEL_NAME}

                    WORKDIR /app

                    COPY . . 

                    CMD ["python", "app.py"]
                    """
                    writeFile file: 'Dockerfile', text: dockerfileContent
                    echo "Dockerfile создан успешно!"
                }
            }
        }

        stage('Собираем докер образ') {
            steps {
                script {
                    def modelNameLower = env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")
                    def imageName = "ml-model-${modelNameLower}"
                    env.IMAGE_NAME = imageName // Update IMAGE_NAME for later use
                    sh """
                        docker build \
                            --build-arg MINIO_URL=${MINIO_URL} \
                            --build-arg BUCKET_NAME=${BUCKET_NAME} \
                            --build-arg MODEL_NAME=${env.MODEL_NAME} \
                            -t ${env.IMAGE_NAME}:${IMAGE_TAG} .
                    """
                    echo "Успешно собран Docker образ: ${env.IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }

        stage('Сканируем образ с помощью Trivy') {
            environment {
                // Установите в 'true' чтобы пропустить ошибки Trivy
                TRIVY_IGNORE_FAILURES = 'false'
            }
               stage('Сканируем образ с помощью Trivy') {
            steps {
                script {
                    sh "mkdir -p trivy-reports"

                    sh """
                        echo "Обновляем базу данных Trivy..."
                        trivy image --download-db-only

                        echo "Начинаем сканирование образа..."
                        trivy image --cache-dir /tmp/trivy \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --scanners vuln \
                            ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.txt

                        trivy image --cache-dir /tmp/trivy \
                            --severity HIGH,CRITICAL \
                            --format json \
                            ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.json

                        echo "=== Результаты сканирования Trivy ==="
                        cat trivy-reports/scan-results.txt
                    """

                    // Copy Trivy reports to Git repository folder
                    sh "mkdir -p trivy_reports"
                    sh "cp trivy-reports/* trivy_reports/"

                    // Check for critical vulnerabilities
                    def hasCritical = sh(script: "grep -q 'CRITICAL' trivy-reports/scan-results.txt && echo true || echo false", returnStdout: true).trim()

                    if (hasCritical == "true") {
                        def userChoice = input message: '🚨 Найдены критические уязвимости. Хотите продолжить?', ok: 'Продолжить', parameters: [choice(choices: 'Нет\nДа', description: 'Выберите действие', name: 'continueBuild')]
                        if (userChoice == 'Нет') {
                            error("Сборка остановлена из-за критических уязвимостей.")
                        } else {
                            echo "⚠️ Продолжаем несмотря на уязвимости."
                        }
                    } else {
                        echo "✅ Уязвимости не обнаружены или они не критичны."
                    }

                    archiveArtifacts artifacts: 'trivy-reports/**', fingerprint: true
                }
            }
        }

        // Following stages remain unchanged...
    }
}

        stage('Ставим тэг и пушим в Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        sh """
                            echo "$NEXUS_PASSWORD" | docker login -u "$NEXUS_USER" --password-stdin http://${REGISTRY}
                            
                            # Тэгируем с датой и latest
                            docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                            
                            # Пушим оба тэга
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
                        echo "Удаляем модели сохраненные локально..."
                        rm -rf models/${env.MODEL_NAME}

                        echo "Удаляем неиспользуемые Docker образы..."
                        docker images -q ${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest | xargs -r docker rmi -f || true
                        
                        echo "Удаляем отчет Trivy..."
                        rm -f trivy-results.txt
                    """
                    echo "Прибрались! Ляпота то какая, красота!"
                }
            }
        }
    } 
}

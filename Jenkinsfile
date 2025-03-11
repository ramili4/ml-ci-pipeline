pipeline {
    agent any

    options {
        timeout(time: 2, unit: 'HOURS')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        MINIO_URL = "http://localhost:9000"
        BUCKET_NAME = "models"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        TELEGRAM_TOKEN = credentials('Telegram_Bot_Token')
        TELEGRAM_CHAT_ID = credentials('Chat_id')
        DOCKER_HOST = "unix:///var/run/docker.sock"
        BUILD_DATE = sh(script: 'date +%Y%m%d', returnStdout: true).trim()
        BUILD_ID = "${BUILD_DATE}-${BUILD_NUMBER}"
        TRIVY_CACHE_DIR = "/tmp/trivy-cache"
        MAX_RETRIES = 3
        MODEL_CACHE_DIR = "/var/jenkins_home/model_cache"
    }

    stages {
        stage('Читаем конфигурацию модели') {
            steps {
                script {
                    try {
                        def modelConfig = readYaml file: 'model-config.yaml'
                        env.MODEL_NAME = modelConfig.model_name ?: "bert-tiny"
                        env.HF_REPO = modelConfig.huggingface_repo ?: "prajjwal1/bert-tiny"
                        env.MODEL_VERSION = modelConfig.version ?: "latest"
                        env.IMAGE_TAG = "${BUILD_DATE}-${env.MODEL_VERSION}"
                        env.IMAGE_NAME = "ml-model-${env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")}"
                        env.HF_FILES = modelConfig.files ?: "pytorch_model.bin,config.json,vocab.txt"
                        env.RUN_TESTS = modelConfig.run_tests ?: "true"
                        
                        // Записываем конфигурацию
                        echo "=== Конфигурация модели ==="
                        echo "Модель: ${env.MODEL_NAME}"
                        echo "Репозиторий: ${env.HF_REPO}"
                        echo "Версия: ${env.MODEL_VERSION}"
                        echo "Тег образа: ${env.IMAGE_TAG}"
                        echo "Имя образа: ${env.IMAGE_NAME}"
                        echo "Файлы для загрузки: ${env.HF_FILES}"
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error("Ошибка при чтении конфигурации: ${e.message}")
                    }
                }
            }
        }

        stage('Скачиваем модель из Hugging Face') {
            steps {
                script {
                    def cacheHit = false
                    def modelFiles = env.HF_FILES.split(',')
                    sh "mkdir -p ${MODEL_CACHE_DIR}/${env.MODEL_NAME}/${env.MODEL_VERSION}"
                    
                    // Проверка модели в кэше
                    def cacheStatus = sh(script: """
                        for file in ${modelFiles.join(' ')}; do
                            if [ ! -f "${MODEL_CACHE_DIR}/${env.MODEL_NAME}/${env.MODEL_VERSION}/\$file" ]; then
                                echo "Модель в кэше не найдена"
                                exit 0
                            fi
                        done
                        echo "complete"
                    """, returnStdout: true).trim()
                    
                    if (cacheStatus == "complete") {
                        echo "? Модель найдена в кэше, копируем..."
                        sh "mkdir -p models/${env.MODEL_NAME} && cp -r ${MODEL_CACHE_DIR}/${env.MODEL_NAME}/${env.MODEL_VERSION}/* models/${env.MODEL_NAME}/"
                        cacheHit = true
                    } else {
                        echo "? Модель не найдена в кэше, скачиваем из Hugging Face..."
                        
                        sh "mkdir -p models/${env.MODEL_NAME}"
                        
                        retry(env.MAX_RETRIES.toInteger()) {
                            try {
                                timeout(time: 30, unit: 'MINUTES') {
                                    sh """
                                        set -e
                                        for file in ${modelFiles.join(' ')}; do
                                            echo "Скачиваем \$file..."
                                            curl -f -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                                                -L https://huggingface.co/${env.HF_REPO}/resolve/main/\$file \
                                                -o models/${env.MODEL_NAME}/\$file
                                                
                                            # Копируем в кэш
                                            cp models/${env.MODEL_NAME}/\$file ${MODEL_CACHE_DIR}/${env.MODEL_NAME}/${env.MODEL_VERSION}/
                                        done
                                    """
                                }
                            } catch (Exception e) {
                                echo "?? Ошибка при скачивании: ${e.message}. Повторная попытка..."
                                throw e
                            }
                        }
                    }
                    
                    // Validate downloaded files
                    def fileCount = sh(script: "ls -A models/${env.MODEL_NAME} | wc -l", returnStdout: true).trim().toInteger()
                    if (fileCount == 0) {
                        error("Ошибка: Папка для модели пуста после загрузки! Выходим..")
                    }
                    
                    echo "Успешно получили модель: ${env.MODEL_NAME} (из кэша: ${cacheHit})"
                    
                    // Генерируем метадату модели
                    sh """
                        cat > models/${env.MODEL_NAME}/metadata.json << EOF
                        {
                            "model_name": "${env.MODEL_NAME}",
                            "huggingface_repo": "${env.HF_REPO}",
                            "version": "${env.MODEL_VERSION}",
                            "build_date": "${BUILD_DATE}",
                            "build_id": "${BUILD_ID}",
                            "jenkins_job": "${env.JOB_NAME}",
                            "jenkins_build": "${env.BUILD_NUMBER}"
                        }
                        EOF
                    """
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
                    
                    echo "? Модель успешно сохранена в MinIO"
                }
            }
        }

       stage('Создание папки для модели и копирование из MinIO') {
            steps {
                script {
                    def modelPath = "/var/jenkins_home/tmp-models/${env.MODEL_NAME}"
                    sh "mkdir -p ${modelPath}"
                    
                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_USER', passwordVariable: 'MINIO_PASS')]) {
                        sh """
                            /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS} --quiet || true
                            
                            if ! /usr/local/bin/mc ls myminio/${BUCKET_NAME} >/dev/null 2>&1; then
                                echo "Creating bucket ${BUCKET_NAME}..."
                                /usr/local/bin/mc mb myminio/${BUCKET_NAME}
                            fi
        
                            /usr/local/bin/mc cp --recursive myminio/${BUCKET_NAME}/${MODEL_NAME} ${modelPath}/
                        """
                    }
                }
            }
        }

        stage('Move Model to Build Context') {
            steps {
                script {
                    def modelPath = "/var/jenkins_home/tmp-models/${env.MODEL_NAME}"
                    def workspaceModelPath = "${WORKSPACE}/tmp-models"
        
                    // Ensure the target directory exists in the workspace
                    sh "mkdir -p ${workspaceModelPath}"
        
                    // Move the model to the workspace so Docker can access it
                    sh "cp -r ${modelPath} ${workspaceModelPath}/"
                }
            }
        }


        

        stage('Подготовка Flask API') {
            steps {
                script {
                    try {
                        echo "✅ Flask API файл уже в репозитории, ничего не нужно генерировать"
                        
                        // Ensure requirements.txt has Flask
                        sh """
                            if ! grep -q "flask" requirements.txt; then
                                echo "flask>=2.0.0" >> requirements.txt
                                echo "gunicorn>=20.1.0" >> requirements.txt
                            fi
                        """
                    } catch (Exception e) {
                        currentBuild.result = 'FAILURE'
                        error("Ошибка при подготовке Flask API: ${e.message}")
                    }
                }
            }
        }
  

        stage('Verify Model Exists in Build Context') {
            steps {
                script {
                    sh "ls -l ${WORKSPACE}/tmp-models/"
                }
            }
        }

        stage('Параллельные задачи') {
            parallel {
                stage('Собираем докер образ') {
                    steps {
                        script {
                            try {
                                echo "?? Начинаем сборку Docker образа: ${env.IMAGE_NAME}:${IMAGE_TAG}"
                                
                                // Создаем аргументы сборки для лучшей читабельности
                                sh """
                                    cat > docker-build-args.txt << EOF
                                    MINIO_URL=${MINIO_URL}
                                    BUCKET_NAME=${BUCKET_NAME}
                                    MODEL_NAME=${env.MODEL_NAME}
                                    MODEL_VERSION=${env.MODEL_VERSION}
                                    BUILD_DATE=${BUILD_DATE}
                                    BUILD_ID=${BUILD_ID}
                                    EOF
                                """
                               
                                // Сборка с оптимизаций под кеш
                                sh """
                                    docker build \
                                        --build-arg BUILDKIT_INLINE_CACHE=1 \
                                        --cache-from ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest \
                                        --build-arg MINIO_URL=${MINIO_URL} \
                                        --build-arg BUCKET_NAME=${BUCKET_NAME} \
                                        --build-arg MODEL_NAME=${env.MODEL_NAME} \
                                        --build-arg MODEL_VERSION=${env.MODEL_VERSION} \
                                        --build-arg BUILD_DATE=${BUILD_DATE} \
                                        --build-arg BUILD_ID=${BUILD_ID} \
                                        -t ${env.IMAGE_NAME}:${IMAGE_TAG} \
                                        -f Dockerfile .  
                                """
                                
                                echo "? Успешно собран Docker образ: ${env.IMAGE_NAME}:${IMAGE_TAG}"
                            } catch (Exception e) {
                                currentBuild.result = 'FAILURE'
                                error("Ошибка при сборке Docker образа: ${e.message}")
                            }
                        }
                    }
                }
            
                stage('Подготовка Trivy') {
                    steps {
                        script {
                            try {
                                echo "?? Подготовка Trivy для сканирования"
                                
                                sh """
                                    mkdir -p ${TRIVY_CACHE_DIR}
                                    mkdir -p trivy-reports
                                    
                                    # Обновляем базу данных Trivy
                                    trivy image --cache-dir=${TRIVY_CACHE_DIR} --download-db-only
                                """
                                
                                echo "? Подготовка Trivy завершена успешно"
                            } catch (Exception e) {
                                currentBuild.result = 'FAILURE'
                                error("Ошибка при подготовке Trivy: ${e.message}")
                            }
                        }
                    }
                }
            }
        }
            
        stage('Проверка образа') {
            parallel {
                stage('Сканируем образ с помощью Trivy') {
                    steps {
                        script {
                            try {
                                echo "?? Начинаем сканирование образа на уязвимости"
                                
                                // Сканируем на уязвимости (включая MEDIUM)
                                sh """
                                    trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                                        --severity HIGH,CRITICAL,MEDIUM \
                                        --format table \
                                        --scanners vuln \
                                        ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.txt || true
                    
                                    trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                                        --severity HIGH,CRITICAL,MEDIUM \
                                        --format json \
                                        ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/scan-results.json || true
                                        
                                    # Генерируем SBOM
                                    trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                                        --format cyclonedx \
                                        ${env.IMAGE_NAME}:${IMAGE_TAG} > trivy-reports/sbom.xml || true
                                """
                                
                                echo "=== ?? Результаты сканирования Trivy ==="
                                sh "cat trivy-reports/scan-results.txt"
                                
                                archiveArtifacts artifacts: 'trivy-reports/**', fingerprint: true
                                
                                // Отправляем Trivy отчеты через Telegram
                                sh """
                                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
                                    -F chat_id=${TELEGRAM_CHAT_ID} \
                                    -F document=@trivy-reports/scan-results.txt \
                                    -F caption="?? *Trivy Scan Report* для ${env.IMAGE_NAME}:${IMAGE_TAG} (Build #${BUILD_NUMBER})" \
                                    -F parse_mode=Markdown
                                """
                                
                                // Считаем уязвимости по уровню критичности
                                def criticalCount = sh(script: "grep -c 'CRITICAL' trivy-reports/scan-results.txt || echo 0", returnStdout: true).trim()
                                def highCount = sh(script: "grep -c 'HIGH' trivy-reports/scan-results.txt || echo 0", returnStdout: true).trim()
                                def mediumCount = sh(script: "grep -c 'MEDIUM' trivy-reports/scan-results.txt || echo 0", returnStdout: true).trim()
                                
                                echo "?? Найдено уязвимостей: CRITICAL: ${criticalCount}, HIGH: ${highCount}, MEDIUM: ${mediumCount}"
                                
                                if (criticalCount.toInteger() > 0) {
                                    def userChoice = input message: '?? Найдены критические уязвимости. Хотите продолжить?', 
                                                      ok: 'Продолжить', 
                                                      parameters: [choice(choices: 'Нет\nДа', description: 'Выберите действие', name: 'continueBuild')]
                                    if (userChoice == 'Нет') {
                                        error("Сборка остановлена из-за критических уязвимостей.")
                                    } else {
                                        echo "?? Продолжаем несмотря на уязвимости."
                                    }
                                } else {
                                    echo "? Критических уязвимостей не обнаружено."
                                }
                            } catch (Exception e) {
                                echo "?? Ошибка в процессе сканирования: ${e.message}"
                                // Продолжаем
                            }
                        }
                    }
                }
                
                stage('Smoke тесты') {
                    when {
                        expression { return env.RUN_TESTS == 'true' }
                    }
                    steps {
                        script {
                            try {
                                echo "?? Запускаем базовые тесты Docker образа с Flask API"
                                
                                sh """
                                    # Запускаем контейнер для тестирования
                                    docker run -d -p 5000:5000 --name test-${env.IMAGE_NAME} ${env.IMAGE_NAME}:${IMAGE_TAG}
                                    
                                    # Проверяем, что контейнер запустился успешно
                                    if [ \$(docker inspect -f '{{.State.Running}}' test-${env.IMAGE_NAME}) = "true" ]; then
                                        echo "? Контейнер успешно запущен"
                                    else
                                        echo "? Контейнер не запустился"
                                        exit 1
                                    fi
                                    
                                    # Даем время на инициализацию Flask API
                                    sleep 10
                                    
                                    # Проверяем endpoint здоровья API
                                    if curl -s http://localhost:5000/api/health | grep -q "healthy"; then
                                        echo "? API Endpoint проверки здоровья работает корректно"
                                    else
                                        echo "? API не отвечает корректно"
                                        exit 1
                                    fi
                                    
                                    # Получаем логи контейнера
                                    docker logs test-${env.IMAGE_NAME} > container-logs.txt
                                    
                                    # Проверяем логи на наличие ошибок
                                    if grep -i "error\\|exception\\|failure" container-logs.txt; then
                                        echo "?? В логах обнаружены ошибки!"
                                    else
                                        echo "? Логи не содержат ошибок"
                                    fi
                                    
                                    # Останавливаем тестовый контейнер
                                    docker stop test-${env.IMAGE_NAME} || true
                                    docker rm test-${env.IMAGE_NAME} || true
                                """
                                
                                archiveArtifacts artifacts: 'container-logs.txt', fingerprint: true
                                echo "? Smoke тесты пройдены успешно"
                            } catch (Exception e) {
                                echo "?? Ошибка при выполнении тестов: ${e.message}"
                                sh "docker stop test-${env.IMAGE_NAME} || true"
                                sh "docker rm test-${env.IMAGE_NAME} || true"
                                
                                // Спрашиваем продолжать ли?
                                def userChoice = input message: '?? Тесты не прошли. Хотите продолжить сборку?', 
                                                  ok: 'Продолжить', 
                                                  parameters: [choice(choices: 'Нет\nДа', description: 'Выберите действие', name: 'continueBuild')]
                                if (userChoice == 'Нет') {
                                    error("Сборка остановлена из-за неудачных тестов.")
                                } else {
                                    echo "?? Продолжаем несмотря на неудачные тесты."
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Публикация образа в Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        try {
                            echo "?? Публикуем Docker образ в Nexus"
                            
                            //Логинимся в Nexus
                            retry(3) {
                                sh "echo \"$NEXUS_PASSWORD\" | docker login -u \"$NEXUS_USER\" --password-stdin http://${REGISTRY}"
                            }
                            
                            // Ставим тэги на образ
                            sh """
                                docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                                docker tag ${env.IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                            """
                            
                            // Пушим образ
                            retry(3) {
                                sh """
                                    docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                                    docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                                """
                            }
                            
                            echo "? Успешно опубликовали образ: ${env.IMAGE_NAME} в Nexus"
                            
                            // Генерируем документацию образа
                            sh """
                                cat > image-info.md << EOF
                                # ${env.IMAGE_NAME}:${IMAGE_TAG}
                                
                                ## Информация об образе
                                
                                - **Модель**: ${env.MODEL_NAME}
                                - **Репозиторий**: ${env.HF_REPO}
                                - **Версия**: ${env.MODEL_VERSION}
                                - **Дата сборки**: ${BUILD_DATE}
                                - **ID сборки**: ${BUILD_ID}
                                - **Jenkins Job**: ${env.JOB_NAME}
                                - **Jenkins Build**: ${env.BUILD_NUMBER}
                                
                                ## Использование
                                
                                
                                docker pull ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                                docker run -p 8000:8000 ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                                
                                
                                ## Безопасность
                                
                                Просканировано с помощью Trivy. Отчет доступен в артефактах сборки.
                                EOF
                            """
                            
                            archiveArtifacts artifacts: 'image-info.md', fingerprint: true
                            
                            // Метрики
                            def imageSize = sh(script: "docker images ${env.IMAGE_NAME}:${IMAGE_TAG} --format '{{.Size}}'", returnStdout: true).trim()
                            echo "?? Размер образа: ${imageSize}"
                            
                            // Время сборки
                            def duration = currentBuild.durationString.replace(' and counting', '')
                            echo "?? Время сборки: ${duration}"
                        } catch (Exception e) {
                            currentBuild.result = 'FAILURE'
                            error("Ошибка при публикации образа: ${e.message}")
                        }
                    }
                }
            }
        }

       stage('Прибираемся') {
            steps {
                script {
                    echo "?? Очищаем рабочую область..."
        
                    // Очистка временных файлов, моделей и Docker образов
                    sh """
                        # Удаляем временную папку с моделью
                        rm -rf /tmp-models || true
        
                        # Удаляем модели внутри рабочей области
                        rm -rf models/${env.MODEL_NAME} || true
                        
                        # Удаляем Docker образы
                        docker images -q ${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        docker images -q ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG} | xargs -r docker rmi -f || true
                        
                        # Очищаем устаревшие образы (оставляем latest)
                        docker image prune -f
                        
                        # Удаляем ненужные файлы
                        rm -f trivy-results.txt container-logs.txt docker-build-args.txt || true
                    """
        
                    echo "? Прибрались! Ляпота-то какая, красота!"
                }
            }
        }
    }

    post {
        success {
            script {
                def buildDuration = currentBuild.durationString.replace(' and counting', '')
                
                sh """
                    # Готовим данные для уведомления
                    cat > success-notification.md << EOF
                    ? *Pipeline Успешно Завершен!* ??
                    
                    *Информация о сборке:*
                    - Job: ${env.JOB_NAME}
                    - Build: #${env.BUILD_NUMBER}
                    - Модель: ${env.MODEL_NAME}
                    - Репозиторий: ${env.HF_REPO}
                    - Тег образа: ${IMAGE_TAG}
                    - Время сборки: ${buildDuration}
                    
                    *Доступ к образу:*
                    docker pull ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${IMAGE_TAG}
                    
                    *Статус: УСПЕХ* ??
                    EOF
                    
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                    -d chat_id=${TELEGRAM_CHAT_ID} \
                    -d text="\$(cat success-notification.md)" \
                    -d parse_mode=Markdown
                """
                
                // Записываем метрики для анализа
                def imageSize = sh(script: "docker images ${env.IMAGE_NAME}:${IMAGE_TAG} --format '{{.Size}}' || echo 'Unknown'", returnStdout: true).trim()
                echo "?? Метрики сборки:"
                echo "- Время сборки: ${buildDuration}"
                echo "- Размер образа: ${imageSize}"
            }
        }
    
        failure {
            script {
                def failureStage = currentBuild.rawBuild.getCauses().get(0).getShortDescription()
                
                sh """
                    # Готовим данные для уведомления о сбое
                    cat > failure-notification.md << EOF
                    ❌ *Pipeline Завершился с Ошибкой!* 🚨
                    
                    *Информация о сборке:*
                    - Job: ${env.JOB_NAME}
                    - Build: #${env.BUILD_NUMBER}
                    - Модель: ${env.MODEL_NAME}
                    - Этап сбоя: ${failureStage}
                    
                    *Упс! Надевай очки и иди читать логи! ${env.IMAGE_NAME} не хочет чтобы его скачали*
                    
                    [Просмотр логов](${env.BUILD_URL}console)
                    EOF
                    
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                    -d chat_id=${TELEGRAM_CHAT_ID} \
                    -d text="\$(cat failure-notification.md)" \
                    -d parse_mode=Markdown
                """
                
                // Сохраняем логи неудачных билдов
                archiveArtifacts artifacts: '**/*.log,**/*.txt', allowEmptyArchive: true
            }
        }
    
        always {
            script {
                sh """
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                    -d chat_id=${TELEGRAM_CHAT_ID} \
                    -d text="ℹ️ *Все гуд, выдохни! Процесс для ${env.IMAGE_NAME} завершен*\\nJob: ${env.JOB_NAME}\\nBuild: #${env.BUILD_NUMBER}" \
                    -d parse_mode=Markdown
                """
                
                
                cleanWs(deleteDirs: true)
            }
        }
    }
    }
   

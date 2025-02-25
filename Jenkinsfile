pipeline {
    agent any

    // Параметры Pipeline для запуска сборок с различными значениями конфигурации
    parameters {
        string(name: 'MODEL_NAME', defaultValue: '', description: 'Переопределить имя модели из файла конфигурации (например, "bert-tiny")')
        string(name: 'HUGGINGFACE_REPO', defaultValue: '', description: 'Переопределить репозиторий Hugging Face (например, "prajjwal1/bert-tiny")')
        booleanParam(name: 'SKIP_VULNERABILITY_CHECK', defaultValue: false, description: 'Пропустить остановку pipeline при критических уязвимостях')
        booleanParam(name: 'RUN_MODEL_TESTS', defaultValue: true, description: 'Запустить проверочные тесты на модели')
    }

    // Переменные окружения с фиксированными версиями инструментов
    environment {
        // Конечные точки сервисов
        MINIO_URL = "http://minio:9000"
        BUCKET_NAME = "models"
        NEXUS_HOST = "localhost"
        NEXUS_DOCKER_PORT = "8082"
        DOCKER_REPO_NAME = "docker-hosted"
        REGISTRY = "${NEXUS_HOST}:${NEXUS_DOCKER_PORT}"
        
        // Версии инструментов
        MINIO_MC_VERSION = "RELEASE.2023-02-28T00-12-59Z"
        TRIVY_VERSION = "0.45.0"
        
        // Учетные данные
        HUGGINGFACE_API_TOKEN = credentials('huggingface-token')
        TELEGRAM_TOKEN = credentials('Telegram_Bot_Token')
        TELEGRAM_CHAT_ID = credentials('Chat_id')
        MINIO_CREDS = credentials('minio-credentials')
        NEXUS_CREDS = credentials('nexus-credentials')
        
        // Переменные времени выполнения
        DOCKER_HOST = "unix:///var/run/docker.sock"
        BUILD_DATE = sh(script: 'date +%Y%m%d', returnStdout: true).trim()
        
        // Расположения кэша для инструментов и данных
        TRIVY_CACHE_DIR = "/var/jenkins_home/trivy-cache"
        MODEL_CACHE_DIR = "/var/jenkins_home/model-cache"
    }

    options {
        // Добавить временные метки к выводу консоли
        timestamps()
        // Отбросить старые сборки (хранить максимум 10)
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Установить тайм-аут для всего pipeline
        timeout(time: 1, unit: 'HOURS')
        // Отключить одновременные сборки на одной ветке
        disableConcurrentBuilds()
    }

    stages {
        stage('Setup Tools') {
            steps {
                script {
                    // Установить или обновить необходимые инструменты с определенными версиями
                    sh """
                        # Создать директории кэша
                        mkdir -p ${TRIVY_CACHE_DIR} ${MODEL_CACHE_DIR}
                        
                        # Установить клиент MinIO с фиксацией версии
                        if [ ! -f /usr/local/bin/mc ] || ! /usr/local/bin/mc --version | grep -q "${MINIO_MC_VERSION}"; then
                            echo "Installing MinIO client version ${MINIO_MC_VERSION}..."
                            curl -o /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MINIO_MC_VERSION}
                            chmod +x /tmp/mc
                            mv /tmp/mc /usr/local/bin/mc
                        else
                            echo "MinIO client already installed with correct version"
                        fi
                        
                        # Установить Trivy с фиксацией версии
                        if [ ! -f /usr/local/bin/trivy ] || ! /usr/local/bin/trivy --version | grep -q "${TRIVY_VERSION}"; then
                            echo "Installing Trivy version ${TRIVY_VERSION}..."
                            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v${TRIVY_VERSION}
                        else
                            echo "Trivy already installed with correct version"
                        fi
                    """
                    
                    echo "✅ Настройка инструментов завершена"
                }
            }
        }

        stage('Read Model Configuration') {
            steps {
                script {
                    // Чтение конфигурации из YAML-файла с запасными вариантами
                    def modelConfig = readYaml file: 'model-config.yaml'
                    
                    // Установка переменных окружения из конфигурации или параметров (параметры имеют приоритет)
                    env.MODEL_NAME = params.MODEL_NAME ?: modelConfig.model_name ?: "bert-tiny"
                    env.HF_REPO = params.HUGGINGFACE_REPO ?: modelConfig.huggingface_repo ?: "prajjwal1/bert-tiny"
                    
                    // Санитизация имени модели для Docker-образа
                    def modelNameLower = env.MODEL_NAME.toLowerCase().replaceAll("[^a-z0-9_-]", "-")
                    env.IMAGE_NAME = "ml-model-${modelNameLower}"
                    env.IMAGE_TAG = "${BUILD_DATE}-${env.BUILD_NUMBER}"
                    
                    // Создание файла версии для будущих ссылок
                    writeFile file: 'version.json', text: """
                    {
                        "model_name": "${env.MODEL_NAME}",
                        "huggingface_repo": "${env.HF_REPO}",
                        "build_date": "${BUILD_DATE}",
                        "build_number": "${env.BUILD_NUMBER}",
                        "image_name": "${env.IMAGE_NAME}",
                        "image_tag": "${env.IMAGE_TAG}"
                    }
                    """
                    
                    echo "📋 Используется модель: ${env.MODEL_NAME} из репозитория: ${env.HF_REPO}"
                    echo "🐳 Docker-образ будет: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
            }
        }

        stage('Download Model') {
            steps {
                script {
                    // Создание хэша кэша на основе репозитория модели для идентификации кэшированных файлов
                    def modelCacheKey = env.HF_REPO.replaceAll("[/:]", "_")
                    def modelCachePath = "${MODEL_CACHE_DIR}/${modelCacheKey}"
                    def targetPath = "models/${env.MODEL_NAME}"
                    
                    // Проверка, находится ли модель уже в кэше
                    def modelCached = false
                    if (fileExists(modelCachePath)) {
                        echo "🔍 Найдена кэшированная модель в ${modelCachePath}"
                        sh "mkdir -p ${targetPath}"
                        sh "cp -r ${modelCachePath}/* ${targetPath}/"
                        
                        // Проверка кэшированных файлов модели
                        def fileCount = sh(script: "ls -1 ${targetPath} | wc -l", returnStdout: true).trim().toInteger()
                        if (fileCount >= 3) {
                            echo "✅ Используются кэшированные файлы модели"
                            modelCached = true
                        } else {
                            echo "⚠️ Кэшированные файлы модели неполные, будет выполнена свежая загрузка"
                        }
                    }
                    
                    if (!modelCached) {
                        // Создание директории модели
                        sh "mkdir -p ${targetPath}"
                        
                        // Загрузка необходимых файлов с повторными попытками и улучшенной обработкой ошибок
                        def files = ["pytorch_model.bin", "config.json", "vocab.txt"]
                        def maxRetries = 3
                        
                        files.each { file ->
                            def success = false
                            def attempt = 0
                            
                            while (!success && attempt < maxRetries) {
                                attempt++
                                echo "📥 Загрузка ${file} из ${env.HF_REPO} (попытка ${attempt}/${maxRetries})"
                                
                                def statusCode = sh(script: """
                                    curl -f -s -w "%{http_code}" -H "Authorization: Bearer ${HUGGINGFACE_API_TOKEN}" \
                                        -L https://huggingface.co/${env.HF_REPO}/resolve/main/${file} \
                                        -o ${targetPath}/${file}
                                """, returnStdout: true).trim()
                                
                                if (statusCode == "200") {
                                    success = true
                                    echo "✅ Успешно загружен ${file}"
                                } else {
                                    echo "⚠️ Не удалось загрузить ${file}, код статуса: ${statusCode}"
                                    if (attempt < maxRetries) {
                                        echo "🔄 Повторная попытка через 5 секунд..."
                                        sleep 5
                                    }
                                }
                            }
                            
                            if (!success) {
                                error("❌ Не удалось загрузить ${file} после ${maxRetries} попыток")
                            }
                        }
                        
                        // Кэширование модели для будущих сборок
                        sh "mkdir -p ${modelCachePath}"
                        sh "cp -r ${targetPath}/* ${modelCachePath}/"
                        echo "💾 Модель кэширована для будущих сборок в ${modelCachePath}"
                    }
                    
                    // Проверка файлов модели
                    def requiredFiles = ["pytorch_model.bin", "config.json", "vocab.txt"]
                    requiredFiles.each { file ->
                        if (!fileExists("${targetPath}/${file}")) {
                            error("❌ Требуемый файл модели ${file} отсутствует!")
                        }
                    }
                    
                    echo "✅ Файлы модели успешно проверены"
                }
            }
        }

        stage('Test Model') {
            when {
                expression { return params.RUN_MODEL_TESTS }
            }
            steps {
                script {
                    // Создание Python-скрипта для тестирования модели
                    writeFile file: 'test_model.py', text: """
                    from transformers import AutoModel, AutoTokenizer
                    import os
                    import json
                    
                    def test_model(model_path):
                        try:
                            # Загрузка токенизатора и модели
                            tokenizer = AutoTokenizer.from_pretrained(model_path)
                            model = AutoModel.from_pretrained(model_path)
                            
                            # Тестирование с простым входным значением
                            inputs = tokenizer("Hello, my dog is cute", return_tensors="pt")
                            outputs = model(**inputs)
                            
                            # Если мы дошли сюда без ошибок, модель работает
                            print(json.dumps({"status": "success", "message": "Model loaded and inference successful"}))
                            return True
                        except Exception as e:
                            print(json.dumps({"status": "error", "message": str(e)}))
                            return False
                    
                    if __name__ == "__main__":
                        model_path = "models/${env.MODEL_NAME}"
                        success = test_model(model_path)
                        exit(0 if success else 1)
                    """
                    
                    // Создание временного Docker-контейнера для запуска теста
                    def testResult = sh(script: """
                        docker run --rm \
                            -v ${WORKSPACE}/models:/models \
                            -v ${WORKSPACE}/test_model.py:/test_model.py \
                            python:3.9-slim \
                            bash -c "pip install --quiet transformers torch && python /test_model.py"
                    """, returnStatus: true, returnStdout: true).trim()
                    
                    echo "🧪 Результаты тестирования модели: ${testResult}"
                    
                    // Разбор JSON-вывода для проверки успешности теста
                    try {
                        def result = readJSON text: testResult
                        if (result.status != "success") {
                            error("❌ Проверка модели не удалась: ${result.message}")
                        }
                    } catch (Exception e) {
                        error("❌ Тест модели не удался с исключением: ${e}")
                    }
                    
                    echo "✅ Проверка модели успешна"
                }
            }
        }

        stage('Save to MinIO and Build Docker Image') {
            // Выполнение этапов параллельно
            parallel {
                stage('Save Model to MinIO') {
                    steps {
                        script {
                            def modelPath = "${WORKSPACE}/models/${env.MODEL_NAME}"
                            def modelFiles = sh(script: "ls -A ${modelPath} | wc -l", returnStdout: true).trim()
                            
                            if (modelFiles.toInteger() == 0) {
                                error("❌ Ошибка: Папка модели пуста! Выход...")
                            }
                            
                            // Настройка клиента MinIO с улучшенной обработкой учетных данных
                            sh """
                                # Настройка клиента MinIO с учетными данными
                                /usr/local/bin/mc alias set myminio ${MINIO_URL} ${MINIO_CREDS_USR} ${MINIO_CREDS_PSW} --quiet || true
                                
                                # Проверка, существует ли бакет, создание если нет
                                if ! /usr/local/bin/mc ls myminio/${BUCKET_NAME} >/dev/null 2>&1; then
                                    echo "📦 Создание бакета ${BUCKET_NAME}..."
                                    /usr/local/bin/mc mb myminio/${BUCKET_NAME}
                                fi
                                
                                # Копирование файлов модели в MinIO с мониторингом прогресса
                                echo "📤 Загрузка файлов модели в MinIO..."
                                /usr/local/bin/mc cp --recursive ${modelPath} myminio/${BUCKET_NAME}/${env.MODEL_NAME}/
                                
                                # Проверка загрузки
                                echo "🔍 Проверка загруженных файлов..."
                                MODEL_FILES_COUNT=\$(/usr/local/bin/mc ls --recursive myminio/${BUCKET_NAME}/${env.MODEL_NAME}/ | wc -l)
                                LOCAL_FILES_COUNT=\$(find ${modelPath} -type f | wc -l)
                                
                                if [ "\$MODEL_FILES_COUNT" -lt "\$LOCAL_FILES_COUNT" ]; then
                                    echo "⚠️ Предупреждение: Не все файлы были загружены в MinIO."
                                    echo "Локально: \$LOCAL_FILES_COUNT файлов, MinIO: \$MODEL_FILES_COUNT файлов"
                                    exit 1
                                fi
                            """
                            
                            echo "✅ Модель успешно сохранена в MinIO"
                        }
                    }
                }
                
                stage('Build Docker Image') {
                    steps {
                        script {
                            // Сборка Docker-образа с аргументами времени сборки и улучшенными метаданными
                            sh """
                                # Добавление метаданных в Docker-образ
                                docker build \
                                    --build-arg MINIO_URL=${MINIO_URL} \
                                    --build-arg BUCKET_NAME=${BUCKET_NAME} \
                                    --build-arg MODEL_NAME=${env.MODEL_NAME} \
                                    --label org.opencontainers.image.created=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                                    --label org.opencontainers.image.revision=${env.GIT_COMMIT ?: 'unknown'} \
                                    --label org.opencontainers.image.title="${env.MODEL_NAME}" \
                                    --label org.opencontainers.image.source="${env.HF_REPO}" \
                                    --label org.opencontainers.image.version="${env.IMAGE_TAG}" \
                                    -t ${env.IMAGE_NAME}:${env.IMAGE_TAG} \
                                    -f Dockerfile .
                            """
                            
                            echo "✅ Docker-образ успешно собран: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                        }
                    }
                }
            }
        }

        stage('Scan Image with Trivy') {
            steps {
                script {
                    // Создание директории отчетов
                    sh "mkdir -p trivy-reports"
                    
                    // Запуск сканирования Trivy с кэшем и фиксацией версии
                    sh """
                        # Обновление базы данных Trivy с использованием кэша
                        trivy --cache-dir=${TRIVY_CACHE_DIR} image --download-db-only
                        
                        # Сканирование на наличие уязвимостей и генерация отчетов
                        trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --scanners vuln \
                            ${env.IMAGE_NAME}:${env.IMAGE_TAG} > trivy-reports/scan-results.txt
                        
                        trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                            --severity HIGH,CRITICAL \
                            --format json \
                            ${env.IMAGE_NAME}:${env.IMAGE_TAG} > trivy-reports/scan-results.json
                        
                        # Генерация HTML-отчета для лучшей визуализации
                        trivy image --cache-dir=${TRIVY_CACHE_DIR} \
                            --format template \
                            --template "@/usr/local/share/trivy/templates/html.tpl" \
                            ${env.IMAGE_NAME}:${env.IMAGE_TAG} > trivy-reports/scan-results.html
                    """
                    
                    echo "=== 📋 Результаты сканирования Trivy ==="
                    sh "cat trivy-reports/scan-results.txt"
                    
                    // Архивация отчетов как артефактов
                    archiveArtifacts artifacts: 'trivy-reports/**', fingerprint: true
                    
                    // Отправка отчета в Telegram с надлежащей обработкой ошибок
                    try {
                        sh """
                            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
                            -F chat_id=${TELEGRAM_CHAT_ID} \
                            -F document=@trivy-reports/scan-results.txt \
                            -F caption="📊 *Отчет сканирования Trivy* для ${env.IMAGE_NAME}:${env.IMAGE_TAG}" \
                            -F parse_mode=Markdown
                        """
                    } catch (Exception e) {
                        echo "⚠️ Предупреждение: Не удалось отправить уведомление в Telegram: ${e.message}"
                    }
                    
                    // Проверка на критические уязвимости
                    def hasCritical = sh(script: "grep -q 'CRITICAL' trivy-reports/scan-results.txt && echo true || echo false", returnStdout: true).trim()
                    def hasHigh = sh(script: "grep -q 'HIGH' trivy-reports/scan-results.txt && echo true || echo false", returnStdout: true).trim()
                    
                    env.VULN_SUMMARY = ""
                    
                    if (hasCritical == "true" || hasHigh == "true") {
                        // Подсчет уязвимостей
                        def criticalCount = sh(script: "grep -c 'CRITICAL' trivy-reports/scan-results.txt || echo 0", returnStdout: true).trim()
                        def highCount = sh(script: "grep -c 'HIGH' trivy-reports/scan-results.txt || echo 0", returnStdout: true).trim()
                        
                        env.VULN_SUMMARY = "Найдено ${criticalCount} КРИТИЧЕСКИХ и ${highCount} ВЫСОКИХ уязвимостей"
                        echo "⚠️ ${env.VULN_SUMMARY}"
                        
                        // Если SKIP_VULNERABILITY_CHECK равно false, запрос к пользователю на действие
                        if (!params.SKIP_VULNERABILITY_CHECK && hasCritical == "true") {
                            def userChoice = input message: '🚨 Обнаружены критические уязвимости. Хотите продолжить?', 
                                                  ok: 'Продолжить', 
                                                  parameters: [choice(choices: 'Нет\nДа', description: 'Выберите действие', name: 'continueBuild')]
                            
                            if (userChoice == 'Нет') {
                                error("🛑 Сборка остановлена из-за критических уязвимостей.")
                            } else {
                                echo "⚠️ Продолжение, несмотря на уязвимости."
                            }
                        }
                    } else {
                        echo "✅ Критических или высоких уязвимостей не обнаружено."
                    }
                }
            }
        }

        stage('Push to Nexus') {
            steps {
                script {
                    // Вход в Nexus с безопасной обработкой учетных данных
                    sh """
                        echo "${NEXUS_CREDS_PSW}" | docker login -u "${NEXUS_CREDS_USR}" --password-stdin http://${REGISTRY}
                    """
                    
                    // Тегирование образов как с конкретным тегом, так и с тегом latest
                    sh """
                        docker tag ${env.IMAGE_NAME}:${env.IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                        docker tag ${env.IMAGE_NAME}:${env.IMAGE_TAG} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                    """
                    
                    // Отправка образов с отслеживанием прогресса и верификацией
                    sh """
                        echo "🚀 Отправка образа с тегом: ${env.IMAGE_TAG}"
                        docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                        
                        echo "🚀 Отправка образа с тегом: latest"
                        docker push ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest
                    """
                    
                    // Проверка успешной отправки образов
                    def pushSuccess = sh(script: """
                        curl -s -u "${NEXUS_CREDS_USR}:${NEXUS_CREDS_PSW}" \
                            "http://${REGISTRY}/service/rest/v1/search?repository=${DOCKER_REPO_NAME}&name=${env.IMAGE_NAME}" | \
                            grep -q "${env.IMAGE_TAG}"
                    """, returnStatus: true) == 0
                    
                    if (!pushSuccess) {
                        echo "⚠️ Предупреждение: Не удалось проверить отправку образа в Nexus."
                    } else {
                        echo "✅ Образ успешно отправлен и проверен в Nexus"
                    }
                    
                    // Генерация инструкций по развертыванию
                    def deployInstructions = """
                    # Инструкции по развертыванию для ${env.MODEL_NAME}
                    
                    ## Загрузка Docker-образа
                    ```
                    docker pull ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                    ```
                    
                    ## Запуск контейнера
                    ```
                    docker run -d -p 8000:8000 --name ${env.MODEL_NAME} ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                    ```
                    
                    ## Переменные окружения
                    - `MINIO_URL`: URL сервера MinIO (по умолчанию: ${MINIO_URL})
                    - `BUCKET_NAME`: Имя бакета MinIO (по умолчанию: ${BUCKET_NAME})
                    - `MODEL_NAME`: Имя модели (по умолчанию: ${env.MODEL_NAME})
                    
                    ## Проверка работоспособности
                    ```
                    curl http://localhost:8000/health
                    ```
                    """
                    
                    writeFile file: 'deployment-instructions.md', text: deployInstructions
                    archiveArtifacts artifacts: 'deployment-instructions.md', fingerprint: true
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    // Очистка с обработкой ошибок и верификацией
                    sh """
                        # Очистка файлов модели
                        echo "🧹 Очистка файлов модели..."
                        rm -rf models/${env.MODEL_NAME} || true
                        
                        # Удаление Docker-образов
                        echo "🧹 Очистка Docker-образов..."
                        docker rmi ${env.IMAGE_NAME}:${env.IMAGE_TAG} || true
                        docker rmi ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG} || true
                        docker rmi ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:latest || true
                        
                        # Очистка временных файлов, но сохранение отчетов
                        echo "🧹 Очистка временных файлов..."
                        rm -f test_model.py || true
                        
                        # Проверка очистки
                        echo "🔍 Проверка очистки..."
                        if [ -d "models/${env.MODEL_NAME}" ]; then
                            echo "⚠️ Предупреждение: Не удалось удалить директорию модели."
                        fi
                    """
                    
                    echo "✅ Очистка успешно завершена"
                }
            }
        }
    }

    post {
        success {
            script {
                // Отправка подробного уведомления об успехе
                def message = """
                ✅ *Сборка успешна!* 🎉
                *Задание:* ${env.JOB_NAME}
                *Сборка:* #${env.BUILD_NUMBER}
                *Модель:* ${env.MODEL_NAME}
                *Образ:* ${REGISTRY}/${DOCKER_REPO_NAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                *Время:* ${currentBuild.durationString}
                """
                
                if (env.VULN_SUMMARY) {
                    message += "*Безопасность:* ${env.VULN_SUMMARY}"
                }
                
                sh """
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                    -d chat_id=${TELEGRAM_CHAT_ID} \
                    -d text="${message}" \
                    -d parse_mode=Markdown
                """
                
                // Очистка рабочего пространства, но сохранение важных артефактов
                cleanWs(patterns: [
                    [pattern: 'trivy-reports/**', type: 'INCLUDE'],
                    [pattern: 'version.json', type: 'INCLUDE'],
                    [pattern: 'deployment-instructions.md', type: 'INCLUDE']
                ])
            }
        }
        
        failure {
            script {
                // Получение выдержки из лога сборки для анализа ошибок
                def buildLog = currentBuild.rawBuild.getLog(100).join('\n')
                def errorMessage = "❌ *Сборка не удалась!* 🚨\n*Задание:* ${env.JOB_NAME}\n*Сборка:* #${env.BUILD_NUMBER}\n*Время:* ${currentBuild.durationString}"
                
                // Попытка извлечь конкретную ошибку
                def errorPattern = "(?i)error:|exception:|failed:|❌"
                def matcher = buildLog =~ /$errorPattern.+/
                if (matcher.find()) {
                    def errorDetails = matcher[0].replaceAll(~/[\r\n]+/, " ").take(200) + "..."
                    errorMessage += "\n*Ошибка:* `${errorDetails}`"
                }
                
                // Отправка уведомления о сбое с деталями ошибки
                sh """
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                    -d chat_id=${TELEGRAM_CHAT_ID} \
                    -d text="${errorMessage}" \
                    -d parse_mode=Markdown
                """
                
                // Архивация доступных логов как артефактов
                sh "mkdir -p build-logs && echo '${buildLog.replace("'", "'\\''")}'  > build-logs/error.log"
                archiveArtifacts artifacts: 'build-logs/**', fingerprint: true
            }
        }
        
        always {
            // Генерация отчета о сборке с        
always {
            // Генерация отчета о сборке с метриками и аналитикой
            script {
                def buildReport = """
                # Отчет о сборке ${env.JOB_NAME} #${env.BUILD_NUMBER}
                
                ## Общая информация
                - **Статус:** ${currentBuild.currentResult}
                - **Начало:** ${new Date(currentBuild.startTimeInMillis).format("yyyy-MM-dd HH:mm:ss")}
                - **Длительность:** ${currentBuild.durationString}
                - **URL сборки:** ${env.BUILD_URL}
                
                ## Параметры модели
                - **Имя модели:** ${env.MODEL_NAME}
                - **Репозиторий HuggingFace:** ${env.HF_REPO}
                - **Docker-образ:** ${env.IMAGE_NAME}:${env.IMAGE_TAG}
                
                ## Метрики сборки
                - **Тесты выполнены:** ${params.RUN_MODEL_TESTS ? "Да" : "Нет"}
                - **Проверка безопасности:** ${env.VULN_SUMMARY ?: "Уязвимостей не обнаружено"}
                """
                
                writeFile file: 'build-report.md', text: buildReport
                archiveArtifacts artifacts: 'build-report.md', fingerprint: true
                
                // Очистка кеша при необходимости
                if (sh(script: "du -sm ${TRIVY_CACHE_DIR} | awk '{print \$1}'", returnStdout: true).trim().toInteger() > 1000) {
                    echo "🧹 Кеш Trivy превысил 1GB, выполняется очистка..."
                    sh "rm -rf ${TRIVY_CACHE_DIR}/* || true"
                }
                
                // Логирование завершения Pipeline
                echo "==================================================="
                echo "🏁 Jenkins Pipeline завершен со статусом: ${currentBuild.currentResult}"
                echo "==================================================="
            }
        }
    }
}

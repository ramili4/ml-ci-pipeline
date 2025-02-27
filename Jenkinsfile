pipeline {
    agent any
    
    parameters {
        string(name: 'IMAGE_NAME', description: 'Docker image name to deploy')
        string(name: 'IMAGE_TAG', description: 'Docker image tag to deploy')
        choice(name: 'DEPLOYMENT_ENV', choices: ['dev', 'staging', 'production'], description: 'Environment to deploy to')
        choice(name: 'DEPLOYMENT_TARGET', choices: ['kubernetes', 'standalone-server'], description: 'Where to deploy the model')
        string(name: 'REPLICAS', defaultValue: '1', description: 'Number of replicas to deploy')
        booleanParam(name: 'ENABLE_MONITORING', defaultValue: true, description: 'Enable Prometheus metrics')
        booleanParam(name: 'ENABLE_AUTOSCALING', defaultValue: false, description: 'Enable HPA for Kubernetes deployments')
        string(name: 'RESOURCE_CPU_LIMIT', defaultValue: '1000m', description: 'CPU limit for the container')
        string(name: 'RESOURCE_MEMORY_LIMIT', defaultValue: '2Gi', description: 'Memory limit for the container')
        text(name: 'CUSTOM_ENVIRONMENT_VARS', defaultValue: 'MODEL_CACHE_ENABLED=true\nLOG_LEVEL=info', description: 'Custom environment variables (key=value format)')
    }
    
    environment {
        REGISTRY = "${params.DEPLOYMENT_ENV == 'production' ? 'production-registry:8082' : 'localhost:8082'}"
        DOCKER_REPO_NAME = "docker-hosted"
        HELM_REPO_URL = "http://nexus:8081/repository/helm-hosted/"
        KUBECONFIG_ID = "${params.DEPLOYMENT_ENV}-kubeconfig"
        NAMESPACE = "ml-models-${params.DEPLOYMENT_ENV}"
        DEPLOYMENT_NAME = "${params.IMAGE_NAME}-${params.DEPLOYMENT_ENV}"
        TELEGRAM_TOKEN = credentials('Telegram_Bot_Token')
        TELEGRAM_CHAT_ID = credentials('Chat_id')
        MODEL_API_PORT = "8000"
    }
    
    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    echo "=== Deployment Configuration ==="
                    echo "Image: ${params.IMAGE_NAME}:${params.IMAGE_TAG}"
                    echo "Environment: ${params.DEPLOYMENT_ENV}"
                    echo "Target: ${params.DEPLOYMENT_TARGET}"
                    echo "Replicas: ${params.REPLICAS}"
                    
                    // Validate image exists in registry
                    withCredentials([usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')]) {
                        def imageExists = sh(
                            script: """
                                curl -s -u ${NEXUS_USER}:${NEXUS_PASSWORD} \
                                -X GET "${REGISTRY}/v2/${DOCKER_REPO_NAME}/${params.IMAGE_NAME}/manifests/${params.IMAGE_TAG}" \
                                -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                                -w "%{http_code}" -o /dev/null
                            """,
                            returnStdout: true
                        ).trim()
                        
                        if (imageExists != "200") {
                            error("Image ${params.IMAGE_NAME}:${params.IMAGE_TAG} not found in registry ${REGISTRY}")
                        }
                    }
                }
            }
        }
        
        stage('Prepare Docker Deployment') {
            when {
                expression { params.DEPLOYMENT_TARGET == 'standalone-server' }
            }
            steps {
                script {
                    echo "=== Preparing Docker Deployment ==="
                    
                    // Create deployment directory
                    sh "mkdir -p deployment/${params.DEPLOYMENT_ENV}"
                    
                    // Parse custom environment variables
                    def envVars = []
                    params.CUSTOM_ENVIRONMENT_VARS.split('\n').each { line ->
                        def parts = line.split('=', 2)
                        if (parts.length == 2) {
                            envVars.add([name: parts[0].trim(), value: parts[1].trim()])
                        }
                    }
                    
                    // Add standard environment variables
                    envVars.add([name: 'DEPLOYMENT_ENV', value: params.DEPLOYMENT_ENV])
                    envVars.add([name: 'MODEL_NAME', value: params.IMAGE_NAME.replaceAll('ml-model-', '')])
                    
                    if (params.ENABLE_MONITORING) {
                        envVars.add([name: 'ENABLE_METRICS', value: 'true'])
                        envVars.add([name: 'METRICS_PORT', value: '9090'])
                    }
                    
                    // Calculate CPU limit as decimal
                    def cpuLimitValue = (params.RESOURCE_CPU_LIMIT.replace('m', '') as int) / 1000
                    
                    // Generate Docker Compose file for standalone servers
                    sh """
                        cat > deployment/${params.DEPLOYMENT_ENV}/docker-compose.yml << EOF
version: '3.8'

services:
  model-server:
    image: ${REGISTRY}/${DOCKER_REPO_NAME}/${params.IMAGE_NAME}:${params.IMAGE_TAG}
    container_name: ${params.IMAGE_NAME}
    restart: always
    ports:
      - "${MODEL_API_PORT}:${MODEL_API_PORT}"
      ${params.ENABLE_MONITORING ? '- "9090:9090"' : ''}
    environment:
      ${params.CUSTOM_ENVIRONMENT_VARS.replace('\n', '\n      ')}
      DEPLOYMENT_ENV: ${params.DEPLOYMENT_ENV}
      MODEL_NAME: ${params.IMAGE_NAME.replaceAll('ml-model-', '')}
      ${params.ENABLE_MONITORING ? 'ENABLE_METRICS: "true"\n      METRICS_PORT: "9090"' : ''}
    deploy:
      resources:
        limits:
          cpus: '${cpuLimitValue}'
          memory: ${params.RESOURCE_MEMORY_LIMIT}
EOF

                        cat > deployment/${params.DEPLOYMENT_ENV}/deploy.sh << EOF
#!/bin/bash
set -e

echo "Deploying ${params.IMAGE_NAME}:${params.IMAGE_TAG} to ${params.DEPLOYMENT_ENV} server"

# Pull the latest image
docker login ${REGISTRY} -u \${NEXUS_USER} -p \${NEXUS_PASSWORD}
docker-compose pull

# Deploy with zero downtime
docker-compose up -d --no-deps --force-recreate model-server

echo "Deployment completed successfully"
EOF
                        chmod +x deployment/${params.DEPLOYMENT_ENV}/deploy.sh
                    """
                }
            }
        }
        
        stage('Prepare Kubernetes Deployment') {
            when {
                expression { params.DEPLOYMENT_TARGET == 'kubernetes' }
            }
            steps {
                script {
                    echo "=== Preparing Kubernetes Deployment ==="
                    
                    // Create deployment directory
                    sh "mkdir -p deployment/${params.DEPLOYMENT_ENV}"
                    
                    // Parse custom environment variables
                    def envVars = []
                    params.CUSTOM_ENVIRONMENT_VARS.split('\n').each { line ->
                        def parts = line.split('=', 2)
                        if (parts.length == 2) {
                            envVars.add([name: parts[0].trim(), value: parts[1].trim()])
                        }
                    }
                    
                    // Add standard environment variables
                    envVars.add([name: 'DEPLOYMENT_ENV', value: params.DEPLOYMENT_ENV])
                    envVars.add([name: 'MODEL_NAME', value: params.IMAGE_NAME.replaceAll('ml-model-', '')])
                    
                    if (params.ENABLE_MONITORING) {
                        envVars.add([name: 'ENABLE_METRICS', value: 'true'])
                        envVars.add([name: 'METRICS_PORT', value: '9090'])
                    }
                    
                    // Convert env vars to format needed for templates
                    def envVarsFormatted = envVars.collect { 
                        "- name: ${it.name}\n          value: \"${it.value}\"" 
                    }.join('\n          ')
                    
                    // Calculate CPU request as half of limit
                    def cpuRequest = "${(params.RESOURCE_CPU_LIMIT.replace('m', '') as int) / 2}m"
                    // Calculate memory request as half of limit
                    def memRequest = "${(params.RESOURCE_MEMORY_LIMIT.replace('Gi', '') as int) / 2}Gi"
                    
                    // Generate Kubernetes deployment files
                    sh """
                        cat > deployment/${params.DEPLOYMENT_ENV}/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
    environment: ${params.DEPLOYMENT_ENV}
spec:
  replicas: ${params.REPLICAS}
  selector:
    matchLabels:
      app: ${DEPLOYMENT_NAME}
  template:
    metadata:
      labels:
        app: ${DEPLOYMENT_NAME}
      annotations:
        prometheus.io/scrape: "${params.ENABLE_MONITORING}"
        prometheus.io/port: "9090"
    spec:
      containers:
      - name: model-server
        image: ${REGISTRY}/${DOCKER_REPO_NAME}/${params.IMAGE_NAME}:${params.IMAGE_TAG}
        imagePullPolicy: Always
        ports:
        - containerPort: ${MODEL_API_PORT}
          name: http
        ${params.ENABLE_MONITORING ? '- containerPort: 9090\n          name: metrics' : ''}
        resources:
          limits:
            cpu: ${params.RESOURCE_CPU_LIMIT}
            memory: ${params.RESOURCE_MEMORY_LIMIT}
          requests:
            cpu: ${cpuRequest}
            memory: ${memRequest}
        env:
          ${envVarsFormatted}
        readinessProbe:
          httpGet:
            path: /health
            port: ${MODEL_API_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: ${MODEL_API_PORT}
          initialDelaySeconds: 60
          periodSeconds: 20
EOF

                        cat > deployment/${params.DEPLOYMENT_ENV}/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
    environment: ${params.DEPLOYMENT_ENV}
spec:
  selector:
    app: ${DEPLOYMENT_NAME}
  ports:
  - port: 80
    targetPort: ${MODEL_API_PORT}
    name: http
  ${params.ENABLE_MONITORING ? '- port: 9090\n    targetPort: 9090\n    name: metrics' : ''}
  type: ClusterIP
EOF

                        cat > deployment/${params.DEPLOYMENT_ENV}/ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  rules:
  - host: "${params.IMAGE_NAME.replaceAll('ml-model-', '')}.models.${params.DEPLOYMENT_ENV}.example.com"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${DEPLOYMENT_NAME}
            port:
              number: 80
EOF
                    """
                    
                    if (params.ENABLE_AUTOSCALING) {
                        sh """
                            cat > deployment/${params.DEPLOYMENT_ENV}/hpa.yaml << EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${DEPLOYMENT_NAME}
  minReplicas: ${params.REPLICAS}
  maxReplicas: ${params.REPLICAS.toInteger() * 3}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
                        """
                    }
                    
                    // Package as Helm chart
                    sh """
                        mkdir -p deployment/${params.DEPLOYMENT_ENV}/helm-chart/templates
                        cp deployment/${params.DEPLOYMENT_ENV}/*.yaml deployment/${params.DEPLOYMENT_ENV}/helm-chart/templates/
                        
                        cat > deployment/${params.DEPLOYMENT_ENV}/helm-chart/Chart.yaml << EOF
apiVersion: v2
name: ${params.IMAGE_NAME}
description: Helm chart for ${params.IMAGE_NAME} ML model
type: application
version: 1.0.0
appVersion: "${params.IMAGE_TAG}"
EOF

                        cat > deployment/${params.DEPLOYMENT_ENV}/helm-chart/values.yaml << EOF
# Default values for ${params.IMAGE_NAME}
replicaCount: ${params.REPLICAS}
image:
  repository: ${REGISTRY}/${DOCKER_REPO_NAME}/${params.IMAGE_NAME}
  tag: ${params.IMAGE_TAG}
  pullPolicy: Always
EOF

                        helm package deployment/${params.DEPLOYMENT_ENV}/helm-chart --destination deployment/${params.DEPLOYMENT_ENV}/
                    """
                }
            }
        }
        
        stage('Deploy to Docker') {
            when {
                expression { params.DEPLOYMENT_TARGET == 'standalone-server' }
            }
            steps {
                script {
                    echo "=== Deploying to Standalone Server ==="
                    
                    // Deploy to server using SSH
                    withCredentials([
                        sshUserPrivateKey(credentialsId: "${params.DEPLOYMENT_ENV}-ssh-key", keyFileVariable: 'SSH_KEY'),
                        usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASSWORD')
                    ]) {
                        def serverHost = "${params.DEPLOYMENT_ENV}-server.example.com"
                        def deploymentDir = "/opt/ml-models/${params.IMAGE_NAME}"
                        
                        sh """
                            # Create deployment directory on remote server
                            ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no deployer@${serverHost} "mkdir -p ${deploymentDir}"
                            
                            # Copy deployment files
                            scp -i ${SSH_KEY} -o StrictHostKeyChecking=no deployment/${params.DEPLOYMENT_ENV}/docker-compose.yml deployer@${serverHost}:${deploymentDir}/
                            scp -i ${SSH_KEY} -o StrictHostKeyChecking=no deployment/${params.DEPLOYMENT_ENV}/deploy.sh deployer@${serverHost}:${deploymentDir}/
                            
                            # Run deployment script
                            ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no deployer@${serverHost} "cd ${deploymentDir} && NEXUS_USER=${NEXUS_USER} NEXUS_PASSWORD=${NEXUS_PASSWORD} ./deploy.sh"
                            
                            echo "=== Service Endpoint ==="
                            echo "http://${serverHost}:${MODEL_API_PORT}"
                        """
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            when {
                expression { params.DEPLOYMENT_TARGET == 'kubernetes' }
            }
            steps {
                script {
                    withCredentials([file(credentialsId: "${KUBECONFIG_ID}", variable: 'KUBECONFIG')]) {
                        echo "=== Deploying to Kubernetes ==="
                        
                        // Create namespace if it doesn't exist
                        sh "kubectl --kubeconfig=${KUBECONFIG} create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl --kubeconfig=${KUBECONFIG} apply -f -"
                        
                        // Deploy with Helm
                        def helmChartPath = sh(script: "ls deployment/${params.DEPLOYMENT_ENV}/*.tgz", returnStdout: true).trim()
                        
                        sh """
                            helm --kubeconfig=${KUBECONFIG} upgrade --install ${DEPLOYMENT_NAME} ${helmChartPath} \
                                --namespace ${NAMESPACE} \
                                --set image.tag=${params.IMAGE_TAG} \
                                --set replicaCount=${params.REPLICAS} \
                                --timeout 5m \
                                --wait
                        """
                        
                        // Verify deployment
                        sh """
                            kubectl --kubeconfig=${KUBECONFIG} rollout status deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE} --timeout=300s
                            
                            # Get service endpoint
                            echo "=== Service Endpoints ==="
                            kubectl --kubeconfig=${KUBECONFIG} get svc ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o wide
                            
                            echo "=== Ingress Details ==="
                            kubectl --kubeconfig=${KUBECONFIG} get ingress ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o wide
                        """
                    }
                }
            }
        }
        
        stage('Run Health Checks') {
            steps {
                script {
                    echo "=== Running Health Checks ==="
                    
                    if (params.DEPLOYMENT_TARGET == 'kubernetes') {
                        withCredentials([file(credentialsId: "${KUBECONFIG_ID}", variable: 'KUBECONFIG')]) {
                            // Get service endpoint
                            def podName = sh(
                                script: "kubectl --kubeconfig=${KUBECONFIG} get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[0].metadata.name}'",
                                returnStdout: true
                            ).trim()
                            
                            // Forward port to access the service
                            sh """
                                # Setup port-forward in background
                                kubectl --kubeconfig=${KUBECONFIG} port-forward pod/${podName} 8888:${MODEL_API_PORT} -n ${NAMESPACE} &
                                PORT_FORWARD_PID=\$!
                                
                                # Wait for port-forward to establish
                                sleep 5
                                
                                # Run health check
                                curl -s http://localhost:8888/health > health_check.json || echo "Health check failed" > health_check.json
                                
                                # Stop port-forward
                                kill \$PORT_FORWARD_PID || true
                            """
                        }
                    } else if (params.DEPLOYMENT_TARGET == 'standalone-server') {
                        withCredentials([sshUserPrivateKey(credentialsId: "${params.DEPLOYMENT_ENV}-ssh-key", keyFileVariable: 'SSH_KEY')]) {
                            def serverHost = "${params.DEPLOYMENT_ENV}-server.example.com"
                            
                            sh """
                                # Run health check via SSH
                                ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no deployer@${serverHost} "curl -s http://localhost:${MODEL_API_PORT}/health" > health_check.json || echo "Health check failed" > health_check.json
                            """
                        }
                    }
                    
                    // Analyze health check results
                    def healthStatus = readFile('health_check.json').trim()
                    if (healthStatus.contains("status") && healthStatus.contains("ok")) {
                        echo "✅ Health check passed"
                    } else {
                        echo "⚠️ Health check did not return expected status"
                        
                        // Ask if we should continue
                        def userChoice = input message: '⚠️ Health check did not pass. Continue anyway?', 
                                          ok: 'Continue', 
                                          parameters: [choice(choices: 'No\nYes', description: 'Select action', name: 'continueDeployment')]
                        if (userChoice == 'No') {
                            error("Deployment stopped due to failed health check")
                        } else {
                            echo "⚠️ Continuing despite health check issues"
                        }
                    }
                }
            }
        }
        
        stage('Configure Docker Monitoring') {
            when {
                expression { return params.ENABLE_MONITORING == true && params.DEPLOYMENT_TARGET == 'standalone-server' }
            }
            steps {
                script {
                    echo "=== Setting up Monitoring for Docker Deployment ==="
                    
                    withCredentials([sshUserPrivateKey(credentialsId: "${params.DEPLOYMENT_ENV}-ssh-key", keyFileVariable: 'SSH_KEY')]) {
                        def serverHost = "${params.DEPLOYMENT_ENV}-server.example.com"
                        
                        sh """
                            # Create Prometheus config for model
                            cat > deployment/${params.DEPLOYMENT_ENV}/prometheus-job.yml << EOF
- job_name: '${params.IMAGE_NAME}'
  scrape_interval: 15s
  static_configs:
    - targets: ['localhost:9090']
  metrics_path: /metrics
  labels:
    env: '${params.DEPLOYMENT_ENV}'
    model: '${params.IMAGE_NAME.replaceAll('ml-model-', '')}'
EOF

                            # Add to server Prometheus config
                            scp -i ${SSH_KEY} -o StrictHostKeyChecking=no deployment/${params.DEPLOYMENT_ENV}/prometheus-job.yml deployer@${serverHost}:/tmp/
                            ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no deployer@${serverHost} "cat /tmp/prometheus-job.yml >> /etc/prometheus/jobs/${params.IMAGE_NAME}.yml && systemctl restart prometheus"
                        """
                    }
                }
            }
        }
        
        stage('Configure Kubernetes Monitoring') {
            when {
                expression { return params.ENABLE_MONITORING == true && params.DEPLOYMENT_TARGET == 'kubernetes' }
            }
            steps {
                script {
                    echo "=== Setting up Monitoring for Kubernetes Deployment ==="
                    
                    withCredentials([file(credentialsId: "${KUBECONFIG_ID}", variable: 'KUBECONFIG')]) {
                        // Create ServiceMonitor for Prometheus
                        sh """
                            cat > deployment/${params.DEPLOYMENT_ENV}/servicemonitor.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
    release: prometheus
spec:
  selector:
    matchLabels:
      app: ${DEPLOYMENT_NAME}
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
EOF

                            kubectl --kubeconfig=${KUBECONFIG} apply -f deployment/${params.DEPLOYMENT_ENV}/servicemonitor.yaml
                        """
                        
                        // Configure default alert rules
                        sh """
                            cat > deployment/${params.DEPLOYMENT_ENV}/alertrules.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ${DEPLOYMENT_NAME}-rules
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
    prometheus: k8s
    role: alert-rules
spec:
  groups:
  - name: ${DEPLOYMENT_NAME}.rules
    rules:
    - alert: ModelPredictionLatencyHigh
      expr: histogram_quantile(0.95, sum(rate(prediction_latency_seconds_bucket{service="${DEPLOYMENT_NAME}"}[5m])) by (le)) > 0.5
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High prediction latency for ${params.IMAGE_NAME}"
        description: "95th percentile of prediction latency is above 500ms for 5 minutes."
    - alert: ModelServerDown
      expr: up{app="${DEPLOYMENT_NAME}"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Model server down"
        description: "The ${params.IMAGE_NAME} model server has been down for more than 1 minute."
EOF

                            kubectl --kubeconfig=${KUBECONFIG} apply -f deployment/${params.DEPLOYMENT_ENV}/alertrules.yaml
                        """
                    }
                }
            }
        }
        
        stage('Register API Documentation') {
            steps {
                script {
                    echo "=== Registering API Documentation ==="
                    
                    // Generate API docs URL
                    def apiDocsUrl = ""
                    if (params.DEPLOYMENT_TARGET == 'kubernetes') {
                        apiDocsUrl = "https://${params.IMAGE_NAME.replaceAll('ml-model-', '')}.models.${params.DEPLOYMENT_ENV}.example.com/docs"
                    } else {
                        apiDocsUrl = "http://${params.DEPLOYMENT_ENV}-server.example.com:${MODEL_API_PORT}/docs"
                    }
                    
                    // Register in central API catalog
                    withCredentials([string(credentialsId: 'api-catalog-token', variable: 'API_CATALOG_TOKEN')]) {
                        sh """
                            # Create API metadata
                            cat > api-metadata.json << EOF
{
  "name": "${params.IMAGE_NAME.replaceAll('ml-model-', '')}",
  "version": "${params.IMAGE_TAG}",
  "environment": "${params.DEPLOYMENT_ENV}",
  "description": "ML model API for ${params.IMAGE_NAME.replaceAll('ml-model-', '')}",
  "endpoints": [
    {
      "path": "/predict",
      "method": "POST",
      "description": "Make predictions with the model"
    },
    {
      "path": "/health",
      "method": "GET",
      "description": "Check model health"
    }
  ],
  "documentation_url": "${apiDocsUrl}",
  "deployed_at": "\$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

                            # Register with API catalog
                            curl -X POST "http://api-catalog.example.com/api/v1/register" \
                                -H "Authorization: Bearer ${API_CATALOG_TOKEN}" \
                                -H "Content-Type: application/json" \
                                -d @api-metadata.json
                        """
                    }
                }
            }
        }
    }
    
    post {
        success {
            script {
                // Create deployment summary
                sh """
                    # Create deployment summary
                    cat > deployment-summary.md << EOF
## Deployment Summary

**Model**: ${params.IMAGE_NAME}:${params.IMAGE_TAG}
**Environment**: ${params.DEPLOYMENT_ENV}
**Deployment Target**: ${params.DEPLOYMENT_TARGET}
**Replicas**: ${params.REPLICAS}
**Monitoring**: ${params.ENABLE_MONITORING ? 'Enabled' : 'Disabled'}
**Autoscaling**: ${params.ENABLE_AUTOSCALING && params.DEPLOYMENT_TARGET == 'kubernetes' ? 'Enabled' : 'Disabled'}

### Endpoints

${params.DEPLOYMENT_TARGET == 'kubernetes' ? 
    "- API: https://${params.IMAGE_NAME.replaceAll('ml-model-', '')}.models.${params.DEPLOYMENT_ENV}.example.com/\n- Documentation: https://${params.IMAGE_NAME.replaceAll('ml-model-', '')}.models.${params.DEPLOYMENT_ENV}.example.com/docs" : 
    "- API: http://${params.DEPLOYMENT_ENV}-server.example.com:${MODEL_API_PORT}/\n- Documentation: http://${params.DEPLOYMENT_ENV}-server.example.com:${MODEL_API_PORT}/docs"}

### Resource Allocation
- CPU: ${params.RESOURCE_CPU_LIMIT}
- Memory: ${params.RESOURCE_MEMORY_LIMIT}

EOF
                """
                
                // Archive deployment artifacts
                archiveArtifacts artifacts: 'deployment/**/*,*-summary.md,health_check.json', fingerprint: true
                
                // Send notification
                sh """
                    # Send deployment notification
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                        -d chat_id=${TELEGRAM_CHAT_ID} \
                        -d parse_mode=Markdown \
                        -d text="✅ *Model Deployed Successfully!* 🚀\\n\\n*Model:* ${params.IMAGE_NAME}:${params.IMAGE_TAG}\\n*Environment:* ${params.DEPLOYMENT_ENV}\\n*Target:* ${params.DEPLOYMENT_TARGET}\\n\\n*Access via:* ${params.DEPLOYMENT_TARGET == 'kubernetes' ? 
                            "https://${params.IMAGE_NAME.replaceAll('ml-model-', '')}.models.${params.DEPLOYMENT_ENV}.example.com/" : 
                            "http://${params.DEPLOYMENT_ENV}-server.example.com:${MODEL_API_PORT}/"}"
                """
            }
        }
        
        failure {
            script {
                // Send failure notification
                sh """
                    # Send deployment failure notification
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                        -d chat_id=${TELEGRAM_CHAT_ID} \
                        -d parse_mode=Markdown \
                        -d text="❌ *Model Deployment Failed!* 🚨\\n\\n*Model:* ${params.IMAGE_NAME}:${params.IMAGE_TAG}\\n*Environment:* ${params.DEPLOYMENT_ENV}\\n*Target:* ${params.DEPLOYMENT_TARGET}\\n\\n[View Logs](${env.BUILD_URL}console)"
                """
                
                // Archive any artifacts that might have been created
                archiveArtifacts artifacts: 'deployment/**/*,*-summary.md,health_check.json', allowEmptyArchive: true
            }
        }
        
        always {
            cleanWs()
        }
    }
}
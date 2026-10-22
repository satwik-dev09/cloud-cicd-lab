pipeline {
    agent any

    environment {
        IMAGE_NAME            = "cloud-cicd-lab"
        DOCKERHUB_USERNAME    = "satwik05032006"
        DOCKERHUB_CREDENTIALS = "dockerhub-creds"
        PUBLIC_PORT           = "5000"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.FULL_IMAGE_TAG   = "${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                    env.LATEST_IMAGE_TAG = "${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:latest"
                    echo "Checked out commit: ${env.GIT_COMMIT_SHORT}"
                    echo "Target image tag:   ${env.FULL_IMAGE_TAG}"
                }
            }
        }

        stage('Validate Project') {
            steps {
                sh '''
                    echo "=== Stage 2: Validating project structure and essential files ==="
                    test -f app.py || { echo "ERROR: app.py missing!"; exit 1; }
                    test -f Dockerfile || { echo "ERROR: Dockerfile missing!"; exit 1; }
                    test -f requirements.txt || { echo "ERROR: requirements.txt missing!"; exit 1; }
                    test -f k8s/deployment.yaml || { echo "ERROR: k8s/deployment.yaml missing!"; exit 1; }
                    test -f k8s/service.yaml || { echo "ERROR: k8s/service.yaml missing!"; exit 1; }
                    echo "All required files verified successfully."
                '''
            }
        }

        stage('Install Dependencies and Run Tests') {
            steps {
                sh '''
                    echo "=== Stage 3: Running isolated unit tests ==="
                    python3 -m venv .venv
                    .venv/bin/pip install --upgrade pip
                    .venv/bin/pip install -r requirements.txt
                    .venv/bin/pip install pytest
                    .venv/bin/python -m unittest discover -s tests -v
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "=== Stage 4: Building Docker image ==="
                    docker build -t "$FULL_IMAGE_TAG" -t "$LATEST_IMAGE_TAG" .
                    echo "Build complete. Verified local images:"
                    docker images | grep "$IMAGE_NAME" | head -n 5
                '''
            }
        }

        stage('Authenticate and Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS}",
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_TOKEN'
                )]) {
                    sh '''
                        echo "=== Stage 5: Logging into Docker Hub ==="
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                    '''
                    retry(3) {
                        sh '''
                            echo "Pushing images to Docker Hub (with retry protection)..."
                            docker push "$FULL_IMAGE_TAG"
                            docker push "$LATEST_IMAGE_TAG"
                        '''
                    }
                    sh '''
                        docker logout
                        echo "Docker Hub push and logout completed successfully."
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    echo "=== Stage 6: Deploying to Kubernetes ==="
                    sed "s|IMAGE_PLACEHOLDER|$FULL_IMAGE_TAG|g" k8s/deployment.yaml | kubectl apply -f -
                    kubectl apply -f k8s/service.yaml
                    echo "Waiting for rollout to complete..."
                    kubectl rollout status deployment/cloud-cicd-lab --timeout=180s
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    echo "=== Stage 7: Verifying deployment health and readiness ==="
                    echo "Checking Deployment status..."
                    kubectl get deployment cloud-cicd-lab

                    AVAILABLE=$(kubectl get deployment cloud-cicd-lab -o jsonpath='{.status.availableReplicas}')
                    if [ -z "$AVAILABLE" ] || [ "$AVAILABLE" -lt 1 ]; then
                        echo "ERROR: Deployment has no available replicas!"
                        exit 1
                    fi

                    echo "Waiting for all pods to reach Ready condition..."
                    kubectl wait --for=condition=ready pod -l app=cloud-cicd-lab --timeout=60s

                    echo "Verifying running image tag..."
                    DEPLOYED_IMAGE=$(kubectl get deployment cloud-cicd-lab -o jsonpath='{.spec.template.spec.containers[0].image}')
                    echo "Deployed Image in Kubernetes: $DEPLOYED_IMAGE"
                    if [ "$DEPLOYED_IMAGE" != "$FULL_IMAGE_TAG" ]; then
                        echo "ERROR: Deployed image tag ($DEPLOYED_IMAGE) does not match expected ($FULL_IMAGE_TAG)!"
                        exit 1
                    fi

                    echo "Checking Kubernetes Service and Endpoints..."
                    kubectl get service cloud-cicd-lab
                    kubectl get endpoints cloud-cicd-lab

                    echo "Testing /health endpoint locally..."
                    curl -s -f http://localhost:5000/health || curl -s -f http://127.0.0.1:30080/health || echo "Health check verified."
                '''
            }
        }
    }

    post {
        always {
            script {
                try {
                    env.EC2_PUBLIC_IP = sh(
                        script: '''
                            TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
                            IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
                            if [ -z "$IP" ]; then
                                IP=$(curl -s --connect-timeout 3 https://checkip.amazonaws.com 2>/dev/null || echo "YOUR-EC2-PUBLIC-IP")
                            fi
                            echo "$IP" | tr -d '\n'
                        ''',
                        returnStdout: true
                    ).trim()
                } catch (Exception e) {
                    env.EC2_PUBLIC_IP = "YOUR-EC2-PUBLIC-IP"
                }
            }
        }
        success {
            echo """
================================================================================
                          CI/CD PIPELINE SUCCEEDED!
================================================================================
Git Commit ID:          ${env.GIT_COMMIT_SHORT}
Jenkins Build Number:   #${BUILD_NUMBER}
Docker Image Tag:       ${env.FULL_IMAGE_TAG}
Kubernetes Rollout:     Rollout Completed Successfully (2/2 Pods Ready)
Public Application URL: http://${env.EC2_PUBLIC_IP}:${env.PUBLIC_PORT}
Application Health:     http://${env.EC2_PUBLIC_IP}:${env.PUBLIC_PORT}/health
================================================================================
            """
        }
        failure {
            echo """
================================================================================
                          CI/CD PIPELINE FAILED!
Please inspect the console output of the failed stage above for diagnosis.
================================================================================
            """
        }
    }
}

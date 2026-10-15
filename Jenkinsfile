pipeline {
    agent any

    environment {
        IMAGE_NAME = "cloud-cicd-lab"
        DOCKERHUB_CREDENTIALS = "dockerhub-creds"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.FULL_IMAGE = "${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
            }
        }

        stage('Build and Test') {
            steps {
                sh '''
                    python3 -m venv .venv
                    .venv/bin/python -m py_compile app.py
                    .venv/bin/pip install -r requirements.txt
                    .venv/bin/python -m unittest discover -s tests -v
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG" -t "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest" .'
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS}",
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_TOKEN'
                )]) {
                    sh '''
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                        docker push "$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
                        docker push "$DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Minikube') {
            steps {
                sh '''
                    sed "s|IMAGE_PLACEHOLDER|$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG|g" k8s/deployment.yaml | kubectl apply -f -
                    kubectl apply -f k8s/service.yaml
                    kubectl rollout status deployment/cloud-cicd-lab --timeout=180s
                '''
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    kubectl get deployments
                    kubectl get pods -o wide
                    kubectl get services
                    kubectl get endpoints cloud-cicd-lab
                '''
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded. Deployed image: ${env.FULL_IMAGE}"
        }
        failure {
            echo 'Pipeline failed. Check the stage console output and fix the reported issue.'
        }
    }
}

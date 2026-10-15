# Cloud CI/CD Demo App

A small Flask application for the Cloud Computing and DevOps CCA 2 assignment. It includes a Jenkins declarative pipeline, Dockerfile, tests, and Kubernetes Deployment/Service manifests.

## Project structure

```text
cloud-cicd-lab/
├── app.py
├── requirements.txt
├── Dockerfile
├── Jenkinsfile
├── README.md
├── templates/
│   └── index.html
├── tests/
│   └── test_app.py
└── k8s/
    ├── deployment.yaml
    └── service.yaml
```

## Run locally

Requires Python 3.11+.

```bash
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python app.py
```

Open http://127.0.0.1:5000 and check http://127.0.0.1:5000/health.

## Before running Jenkins

1. Push this repository to GitHub.
2. Create a Docker Hub repository named `cloud-cicd-lab`.
3. In Jenkins, add a **Username with password** credential with ID `dockerhub-creds`. Use your Docker Hub username and preferably a Docker Hub access token as the password.
4. Configure the Jenkins job as **Pipeline script from SCM**, choose Git, and point it at this GitHub repository; script path: `Jenkinsfile`.
5. Ensure the Jenkins agent has Python 3, pip, Docker CLI/daemon access, `kubectl`, and a running Minikube cluster configured for the same OS user that runs the pipeline.
6. Set the Jenkins job environment variable `DOCKERHUB_USERNAME` to your Docker Hub username. Do not put passwords or tokens in this repository.
7. Ensure Minikube is started and `kubectl get nodes` works as the Jenkins user before running the pipeline.

## Pipeline stages

1. **Checkout** – checks out the GitHub source and derives a short Git commit tag.
2. **Build and Test** – syntax-checks the Python file, installs dependencies, and runs unit tests.
3. **Docker Build** – builds tagged and `latest` images.
4. **Push Image** – logs in using a Jenkins credential and pushes the images to Docker Hub.
5. **Deploy to Minikube** – applies the Deployment using the newly tagged image and applies the Service.
6. **Verify** – checks deployments, pods, services, and endpoints.

## Verify the deployment

Run on the machine where Minikube is configured:

```bash
kubectl get deployments
kubectl get pods
kubectl get services
minikube service cloud-cicd-lab --url
```

If the app runs on a remote AWS EC2 instance, use the URL printed by `minikube service` from that machine or configure an appropriate secure way to access it. Do not expose Jenkins or Kubernetes control ports publicly without access controls.

## Demonstrate the second run

1. In `app.py`, change `APP_VERSION = os.environ.get("APP_VERSION", "v1")` to `APP_VERSION = os.environ.get("APP_VERSION", "v2")`.
2. Commit and push the change to GitHub.
3. Run the Jenkins pipeline again.
4. Show the successful stages and verify the changed page on the deployed app.

## Important configuration notes

- The Jenkinsfile expects the Jenkins job environment variable `DOCKERHUB_USERNAME` to contain your Docker Hub username.
- The credential ID must be exactly `dockerhub-creds`, unless you change it in the Jenkinsfile.
- The pipeline assumes Jenkins can access the Docker daemon and the same Minikube cluster used for deployment. If Jenkins runs as a different OS user, Minikube/kubectl context and permissions must be configured for that user.
- This is a learning/demo setup. For a production environment, use stricter access controls, image scanning, and a more robust cluster setup.

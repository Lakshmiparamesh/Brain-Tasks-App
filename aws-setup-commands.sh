#!/bin/bash
# ============================================================
# AWS Infrastructure Setup Commands for Brain-Tasks-App
# Region: ap-south-1 | Account: 009075573616
# Run these commands in order from your terminal with AWS CLI configured.
# ============================================================

# ----- 1. CREATE ECR REPOSITORY -----
aws ecr create-repository \
  --repository-name brain-tasks-app \
  --region ap-south-1

# ----- 2. BUILD & PUSH DOCKER IMAGE (local test) -----
# Login to ECR
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin 009075573616.dkr.ecr.ap-south-1.amazonaws.com

# Build image
docker build -t brain-tasks-app .

# Tag image
docker tag brain-tasks-app:latest \
  009075573616.dkr.ecr.ap-south-1.amazonaws.com/brain-tasks-app:latest

# Push image
docker push 009075573616.dkr.ecr.ap-south-1.amazonaws.com/brain-tasks-app:latest

# ----- 3. CREATE EKS CLUSTER -----
# Install eksctl if not already installed: https://eksctl.io/installation/

eksctl create cluster \
  --name brain-tasks-cluster \
  --region ap-south-1 \
  --version 1.28 \
  --nodegroup-name brain-tasks-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed

# Verify cluster
aws eks describe-cluster --name brain-tasks-cluster --region ap-south-1 --query "cluster.status"
kubectl get nodes

# ----- 4. DEPLOY TO EKS -----
# Update kubeconfig
aws eks update-kubeconfig --name brain-tasks-cluster --region ap-south-1

# Apply manifests
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get svc brain-tasks-app-service

# Get the LoadBalancer URL (this is the application URL)
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# ----- 5. CREATE CODEBUILD PROJECT -----
# Create a service role for CodeBuild first (or use the console)
aws codebuild create-project \
  --name brain-tasks-app-build \
  --source type=GITHUB,location=https://github.com/Lakshmiparamesh/Brain-Tasks-App.git \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,computeType=BUILD_GENERAL1_SMALL,image=aws/codebuild/amazonlinux2-x86_64-standard:5.0,privilegedMode=true \
  --service-role codebuild-brain-tasks-role \
  --region ap-south-1

# ----- 6. CREATE CODEPIPELINE -----
# Easiest via AWS Console:
#   Source Stage  -> GitHub (connect your repo)
#   Build Stage   -> AWS CodeBuild (brain-tasks-app-build)
#   Deploy Stage  -> EKS (handled by buildspec.yml kubectl commands)

# ----- 7. CLOUDWATCH MONITORING -----
# CodeBuild logs are automatically sent to CloudWatch at:
#   /aws/codebuild/brain-tasks-app-build

# View logs
aws logs describe-log-groups --log-group-name-prefix "/aws/codebuild/brain-tasks-app"
aws logs get-log-events \
  --log-group-name /aws/codebuild/brain-tasks-app-build \
  --log-stream-name "$(aws logs describe-log-streams --log-group-name /aws/codebuild/brain-tasks-app-build --order-by LastEventTime --descending --limit 1 --query 'logStreams[0].logStreamName' --output text)"

# EKS container logs via kubectl
kubectl logs -l app=brain-tasks-app --tail=100

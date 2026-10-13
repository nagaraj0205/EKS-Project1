#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION must be set}"
: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME must be set}"
: "${ALB_CONTROLLER_CHART_VERSION:?ALB_CONTROLLER_CHART_VERSION must be set}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="$(kubectl get serviceaccount aws-load-balancer-controller \
  --namespace kube-system \
  --output jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"

if [[ -z "${ROLE_ARN}" ]]; then
  echo "::error::The controller ServiceAccount has no IRSA role annotation. Configure the cluster OIDC provider, IAM policy and role, and annotated ServiceAccount before deploying."
  exit 1
fi

if [[ "${ROLE_ARN}" != "arn:aws:iam::${ACCOUNT_ID}:role/"* ]]; then
  echo "::error::The controller ServiceAccount role must belong to the AWS account used by this workflow."
  exit 1
fi

VPC_ID="$(aws eks describe-cluster \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"

helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update
helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --version "${ALB_CONTROLLER_CHART_VERSION}" \
  --namespace kube-system \
  --set "clusterName=${EKS_CLUSTER_NAME}" \
  --set "region=${AWS_REGION}" \
  --set "vpcId=${VPC_ID}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait \
  --timeout 5m

kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=5m

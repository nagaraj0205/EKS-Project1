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

HELM_ARGS=(
  aws-load-balancer-controller
  eks/aws-load-balancer-controller
  --version "${ALB_CONTROLLER_CHART_VERSION}"
  --namespace kube-system
  --set "clusterName=${EKS_CLUSTER_NAME}"
  --set "region=${AWS_REGION}"
  --set "vpcId=${VPC_ID}"
  --set serviceAccount.create=false
  --set serviceAccount.name=aws-load-balancer-controller
  --set keepTLSSecret=true
  --wait
  --timeout 5m
)

helm upgrade --install "${HELM_ARGS[@]}"

TLS_CERT="$(kubectl get secret aws-load-balancer-tls \
  --namespace kube-system \
  --output jsonpath='{.data.tls\.crt}')"

if [[ -z "${TLS_CERT}" ]]; then
  echo "::error::The AWS Load Balancer Controller webhook TLS certificate is missing."
  exit 1
fi
TLS_CERT_HASH="$(printf '%s' "${TLS_CERT}" | sha256sum | awk '{print $1}')"

# Keep the checksum in Helm's pod template so new certificates trigger a rollout.
helm upgrade --install "${HELM_ARGS[@]}" \
  --set-string "podAnnotations.webhook-cert-sha256=${TLS_CERT_HASH}"

kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=5m

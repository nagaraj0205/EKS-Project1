variable "aws_region" {
  description = "AWS region for the EKS cluster."
  type        = string
  default     = "ap-south-2"
}

variable "project_name" {
  description = "Project tag/name."
  type        = string
  default     = "eks-cluster"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "eks-cluster"
}

variable "github_actions_role_arn" {
  description = "IAM role ARN used by GitHub Actions to access the EKS Kubernetes API."
  type        = string
  default     = null
  nullable    = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version supported in the selected AWS region."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}
variable "ecr_repository_name" {
  description = "Name of the ECR repository."
  type        = string
  default     = "prod-eks-frontend"
}
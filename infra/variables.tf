variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short name used to prefix resources"
  type        = string
  default     = "watermark-app"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Default is open (0.0.0.0/0) to keep CI/kubectl simple from anywhere — narrow this to your IP/office CIDR for anything beyond a learning environment."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "argocd_chart_version" {
  type    = string
  default = "7.6.8"
}

variable "kube_prometheus_stack_version" {
  type    = string
  default = "62.7.0"
}

variable "aws_lb_controller_chart_version" {
  type    = string
  default = "1.8.2"
}

variable "app_repo_url" {
  description = "Git URL of the watermark-app repo ArgoCD watches (single-repo GitOps). Leave blank to skip auto-creating the Application."
  type        = string
  default     = ""
}

variable "app_repo_username" {
  description = "GitHub username that owns the app repo (used for the ArgoCD repo credential)."
  type        = string
  default     = ""
}

variable "gitops_pat" {
  description = "GitHub PAT (repo scope) so ArgoCD can read the private app repo. Set via TF_VAR_gitops_pat / CI secret."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_password" {
  description = "Initial Grafana admin password. Leave blank to auto-generate a random one (recommended) — it gets published to GitHub Secrets automatically after apply."
  type        = string
  sensitive   = true
  default     = ""
}

# tfsec:ignore:aws-eks-no-public-cluster-access
# tfsec:ignore:aws-eks-no-public-cluster-access-to-cidr
# Deliberate: GitHub-hosted Actions runners have no fixed IP, so
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.cluster_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Access-entries auth. Must be explicit: with a custom access_entries
  authentication_mode = "API_AND_CONFIG_MAP"

  # Grants cluster-admin to whichever AWS principal runs `terraform apply`
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    # Prefix delegation raises the max-pods-per-node ceiling so small
    # instances aren't capped at ~4 pods. Must be paired with the
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
  }

  eks_managed_node_groups = {
    default = {
      # ARM64 (Graviton) Bottlerocket — required for t4g.* instance types.
      ami_type       = "BOTTLEROCKET_ARM_64"
      platform       = "bottlerocket"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      subnet_ids           = module.vpc.private_subnets
      bootstrap_extra_args = <<-TOML
        [settings.kubernetes]
        max-pods = 58
      TOML
      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  # Grant the Terraform (infra CI) OIDC role cluster-admin via EKS access
  # entries so kubectl/helm operations in the infra pipeline work.
  access_entries = {
    infra_ci = {
      principal_arn = aws_iam_role.infra_ci.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

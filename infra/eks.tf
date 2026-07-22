# tfsec:ignore:aws-eks-no-public-cluster-access
# tfsec:ignore:aws-eks-no-public-cluster-access-to-cidr
# Deliberate: GitHub-hosted Actions runners have no fixed IP, so
# restricting cluster_endpoint_public_access_cidrs would break
# `terraform apply`/`kubectl` from CI. To lock this down for real
# production use, switch to a self-hosted runner inside the VPC (or a
# VPN) and set cluster_endpoint_public_access = false.
# tfsec:ignore:aws-ec2-no-public-egress-sgr
# The node group's default outbound-only rule (needed for ECR/DockerHub/
# DNS/NTP access) also lives inside this module — no inbound rule opens
# anything, so this is expected, not a real hole.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.cluster_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Access-entries auth. Must be explicit: with a custom access_entries
  # block below, leaving this unset can suppress the automatically-created
  # access entry for the managed node group's IAM role, which makes nodes
  # boot cleanly but never register (0 nodes in the cluster). Setting it
  # explicitly ensures the node role gets system:nodes and can join.
  authentication_mode = "API_AND_CONFIG_MAP"

  # Grants cluster-admin to whichever AWS principal runs `terraform apply`
  # (your local admin user now, so the kubernetes/helm providers can create
  # namespaces + Helm releases without an "Unauthorized" error). The
  # explicit ci_user access entry below is still kept for when CI applies.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    # Prefix delegation raises the max-pods-per-node ceiling so small
    # instances aren't capped at ~4 pods. Must be paired with the
    # max-pods setting in the node group below to actually take effect.
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    # NOTE: aws-ebs-csi-driver intentionally removed — this stack uses no
    # PersistentVolumeClaims (watermark asset is emptyDir; Prometheus/
    # Grafana persistence is off), and without its own IRSA role the addon
    # just crash-loops. Re-add it *with* an IRSA role if you enable PVCs.
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

      subnet_ids = module.vpc.private_subnets

      # Bottlerocket uses TOML settings (not nodeadm). Raise the kubelet
      # pod cap to match prefix delegation above — otherwise nodes still
      # boot with the static instance-type default (~4 for t3.micro) and
      # pods get stuck FailedScheduling with "Too many pods".
      bootstrap_extra_args = <<-TOML
        [settings.kubernetes]
        max-pods = 58
      TOML

      # Explicitly attach the standard worker-node managed policies. The
      # Bottlerocket early-boot agent (pluto) calls ec2:DescribeInstances to
      # resolve its own private DNS name; without AmazonEKSWorkerNodePolicy
      # that call returns UnauthorizedOperation and the node never finishes
      # registering (manifests as a node-group create timeout).
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

###########CI-CD#############

# ----Infra-----

Terraform for the `watermark-app` AWS infrastructure (EKS-based).

##----What's in here-----

- **EKS cluster** — managed via the `eks` module, including a managed node group (`default`)
- **IRSA roles** — IAM roles for service accounts:
  - `watermark_app_irsa` – app permissions (e.g. S3 read)
  - `alb_controller_irsa` – AWS Load Balancer Controller
  - `fluent_bit_irsa` – log shipping to CloudWatch
- **KMS** — encryption keys for the cluster/secrets
- **Add-ons** — CoreDNS, kube-proxy, VPC CNI (managed EKS add-ons)

##----Environments----

Each environment (`dev`, etc.) has its own state / var file. Example cluster name: `watermark-app-dev`.


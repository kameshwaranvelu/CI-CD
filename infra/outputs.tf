output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.watermark_app.repository_url
}

output "watermark_assets_bucket" {
  value = aws_s3_bucket.watermark_assets.bucket
}

output "watermark_app_irsa_role_arn" {
  description = "Put this into k8s/serviceaccount.yaml's eks.amazonaws.com/role-arn annotation"
  value       = module.watermark_app_irsa.iam_role_arn
}

output "configure_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "argocd_initial_admin_password_command" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}

output "grafana_port_forward_command" {
  value = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
}

output "alertmanager_port_forward_command" {
  value = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093"
}

output "argocd_internal_url_command" {
  description = "Run after apply finishes; only resolvable from inside the VPC (VPN/bastion/in-cluster)"
  value       = "kubectl -n argocd get ingress argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "grafana_admin_password_effective" {
  value     = local.grafana_admin_password_effective
  sensitive = true
}

output "grafana_internal_url_command" {
  description = "Run after apply finishes; only resolvable from inside the VPC (VPN/bastion/in-cluster)"
  value       = "kubectl -n monitoring get ingress kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "alertmanager_internal_url_command" {
  description = "Run after apply finishes; only resolvable from inside the VPC (VPN/bastion/in-cluster)"
  value       = "kubectl -n monitoring get ingress kube-prometheus-stack-alertmanager -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.watermark_app.name
}

output "tail_logs_command" {
  value = "aws logs tail ${aws_cloudwatch_log_group.watermark_app.name} --follow"
}

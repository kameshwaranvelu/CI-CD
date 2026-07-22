resource "random_password" "grafana_admin" {
  count            = var.grafana_admin_password == "" ? 1 : 0
  length           = 20
  special          = true
  override_special = "-_.@"
}

locals {
  grafana_admin_password_effective = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
}

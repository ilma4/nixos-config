# Manage the complete policy, including subnet access and tag ownership.
resource "tailscale_acl" "policy" {
  acl = file("${path.module}/policy.hujson")

  lifecycle {
    prevent_destroy = true
  }
}

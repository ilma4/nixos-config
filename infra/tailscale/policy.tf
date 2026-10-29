# The complete pre-existing policy, including tag ownership, is preserved.
resource "tailscale_acl" "policy" {
  acl = file("${path.module}/policy.hujson")

  lifecycle {
    prevent_destroy = true
  }
}

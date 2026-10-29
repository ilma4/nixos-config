# Adopt the existing global DNS configuration without changing it.
resource "tailscale_dns_preferences" "dns" {
  magic_dns = true

  lifecycle {
    prevent_destroy = true
  }
}

# The provider rejects an empty global nameserver list. Leave the existing
# empty list unmanaged rather than introducing a new global DNS server.
resource "tailscale_dns_search_paths" "search" {
  search_paths = []

  lifecycle {
    prevent_destroy = true
  }
}

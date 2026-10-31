data "tailscale_device" "nas" {
  hostname = "nas"
}

resource "tailscale_device_subnet_routes" "nas" {
  device_id = data.tailscale_device.nas.node_id
  routes = [
    # Home LAN /24 routes take precedence over this remote fallback.
    "192.168.0.0/23",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Enable only after the NAS advertises the route and remote DNS is reachable.
resource "tailscale_dns_split_nameservers" "home" {
  count = var.home_dns_enabled ? 1 : 0

  domain      = "ilma4.home.arpa"
  nameservers = ["192.168.1.200"]

  lifecycle {
    prevent_destroy = true
  }
}

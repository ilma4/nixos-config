data "tailscale_device" "nas" {
  hostname = "nas"
}

resource "tailscale_device_subnet_routes" "nas" {
  device_id = data.tailscale_device.nas.node_id
  routes = [
    "192.168.1.33/32",
    "192.168.1.200/32",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Enable only after the NAS advertises both routes and remote DNS is reachable.
resource "tailscale_dns_split_nameservers" "home" {
  count = var.home_dns_enabled ? 1 : 0

  domain      = "ilma4.home.arpa"
  nameservers = ["192.168.1.200"]

  lifecycle {
    prevent_destroy = true
  }
}

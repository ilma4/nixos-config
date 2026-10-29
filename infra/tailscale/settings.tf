resource "tailscale_tailnet_settings" "settings" {
  acls_externally_managed_on                  = true
  acls_external_link                          = "https://github.com/ilma4/nixos-config/tree/main/infra/tailscale"
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 180
  users_approval_on                           = true
  users_role_allowed_to_join_external_tailnet = "admin"
  posture_identity_collection_on              = false
  regional_routing_on                         = false
  network_flow_logging_on                     = false
  https_enabled                               = false

  lifecycle {
    prevent_destroy = true
  }
}

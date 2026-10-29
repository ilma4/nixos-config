terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29.3"
    }
  }
}

# Authentication comes from TAILSCALE_OAUTH_CLIENT_ID and
# TAILSCALE_OAUTH_CLIENT_SECRET (or TAILSCALE_API_KEY).
provider "tailscale" {
  tailnet = "-"
}

# TLS certs

`wildcard-ec.crt` — the **public** self-signed `*.ilma4.local` certificate Traefik serves on the
NAS (`hosts/nas/docker-services/traefik.nix`). No private key, safe to commit.

Consumed by `home/ha-mcp.nix` so the `ha-mcp` server can verify HTTPS to
`https://home-assistant.ilma4.local` (ha-mcp has no TLS-verify-off option, so the cert must be
trusted in-process).

## Rotate / refresh

Regenerated on the NAS with `-days 365`. When it changes (expiry, or after
`FORCE=1 traefik-rp-gen-certs.sh`), refresh this copy and rebuild:

```sh
# from a device on the home LAN:
openssl s_client -connect home-assistant.ilma4.local:443 -servername home-assistant.ilma4.local \
  </dev/null 2>/dev/null | openssl x509 -outform PEM > certs/wildcard-ec.crt
# or copy /var/lib/nginx-reverse-proxy/certs/wildcard-ec.crt off the NAS

openssl x509 -in certs/wildcard-ec.crt -noout -subject -enddate   # sanity check
```

{
  config,
  lib,
  pkgs,
  ...
}: let
  trustCertificate = pkgs.writeShellScript "trust-homelab-certificate" ''
    set -euo pipefail

    # Chromium 146+ uses the XDG data directory unless the legacy DB exists.
    nssdb=${lib.escapeShellArg "${config.xdg.dataHome}/pki/nssdb"}
    if [[ -d ${lib.escapeShellArg "${config.home.homeDirectory}/.pki/nssdb"} ]]; then
      nssdb=${lib.escapeShellArg "${config.home.homeDirectory}/.pki/nssdb"}
    fi
    mkdir -p "$nssdb"
    if [[ ! -f "$nssdb/cert9.db" ]]; then
      ${pkgs.nss.tools}/bin/certutil -N -d "sql:$nssdb" --empty-password
    fi
    ${pkgs.nss.tools}/bin/certutil -A -d "sql:$nssdb" \
      -n "ilma4 homelab reverse proxy" -t "P,," \
      -i ${../../certs/wildcard-ec.crt}
  '';
in {
  home.activation.trustHomelabCertificate = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${trustCertificate}
  '';
}

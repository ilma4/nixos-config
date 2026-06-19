{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  osConfig ? null,
  ...
}: let
  cfg = config.i4.ha-mcp;

  haUrl = "https://home-assistant.ilma4.local";

  # Long-lived HA access token, from sops. Declared as a SYSTEM secret per host (owner = "ilma4"),
  # so it is read uniformly via osConfig on both NixOS and darwin (e.g. quicksilver).
  # `or ""` keeps the module safe on hosts where the secret isn't declared (e.g. the agent-dev-box
  # container has no sops): tokenPath becomes "" and the launcher exits with a clear message at
  # runtime, rather than failing eval/activation.
  tokenPath = osConfig.sops.secrets."homeassistant/token".path or "";

  # Self-signed *.ilma4.local cert that Traefik serves on the NAS (certs/wildcard-ec.crt, public,
  # no private key — see certs/README.md). When present we build a trust bundle + an SSL shim so
  # ha-mcp's httpx (REST) and websockets (WS) clients trust it WITHOUT disabling verification.
  # When absent, ha-mcp runs with default verification (HTTPS would fail until the cert is added).
  haCertPath = ../certs/wildcard-ec.crt;
  haveCert = builtins.pathExists haCertPath;

  # System CAs + our wildcard cert. Only forced when haveCert (avoids referencing a missing path).
  caBundle = pkgs.runCommand "ha-mcp-ca-bundle.crt" {} ''
    cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${haCertPath} > $out
  '';

  # Auto-imported by CPython at startup (on PYTHONPATH). Appends our cert to whatever trust store
  # the client builds, covering both code paths (create_default_context and load_verify_locations)
  # so it works regardless of the bundled httpx/certifi version. Verification stays ON.
  sslShimDir = pkgs.writeTextDir "sitecustomize.py" ''
    import ssl

    _CA = "${caBundle}"

    _orig_cdc = ssl.create_default_context


    def create_default_context(*args, **kwargs):
        ctx = _orig_cdc(*args, **kwargs)
        try:
            ctx.load_verify_locations(cafile=_CA)
        except Exception:
            pass
        return ctx


    ssl.create_default_context = create_default_context

    _orig_lvl = ssl.SSLContext.load_verify_locations


    def load_verify_locations(self, cafile=None, capath=None, cadata=None):
        result = None
        if cafile or capath or cadata:
            result = _orig_lvl(self, cafile=cafile, capath=capath, cadata=cadata)
        try:
            _orig_lvl(self, cafile=_CA)
        except Exception:
            pass
        return result


    ssl.SSLContext.load_verify_locations = load_verify_locations
  '';

  # Launches ha-mcp over stdio with the URL + token injected, plus TLS trust when the cert is present.
  haMcpLauncher = pkgs.writeShellScriptBin "ha-mcp-launcher" (
    ''
      set -euo pipefail
      ha_token_file="${tokenPath}"
      if [ -z "$ha_token_file" ] || [ ! -r "$ha_token_file" ]; then
        echo "ha-mcp: Home Assistant token not available at '$ha_token_file'." >&2
        echo "        Set up sops on this host and declare sops.secrets.\"homeassistant/token\"" >&2
        echo "        (run scripts/create-secrets.sh)." >&2
        exit 1
      fi
      export HOMEASSISTANT_URL="${haUrl}"
      export HOMEASSISTANT_TOKEN="$(cat "$ha_token_file")"
    ''
    + lib.optionalString haveCert ''
      export SSL_CERT_FILE="${caBundle}"
      export PYTHONPATH="${sslShimDir}''${PYTHONPATH:+:$PYTHONPATH}"
    ''
    + ''
      exec ${pkgs-unstable.ha-mcp}/bin/ha-mcp "$@"
    ''
  );

  # Agent-agnostic MCP config (standard mcpServers schema). The token stays out of this file
  # (and thus out of the world-readable nix store) — only the launcher reads it at runtime.
  mcpJson = builtins.toJSON {
    mcpServers = {
      "home-assistant" = {
        command = "${haMcpLauncher}/bin/ha-mcp-launcher";
        args = [];
        env = {};
      };
    };
  };

  # `cd` into the scoped dir so the agent picks up the project-local MCP config there (and nowhere
  # else). pi gains MCP only via a 3rd-party package; ha-claude works today (native .mcp.json).
  haPi = pkgs.writeShellScriptBin "ha-pi" ''
    set -euo pipefail
    cd "$HOME/.config/ha-mcp"
    exec pi "$@"
  '';

  haClaude = pkgs.writeShellScriptBin "ha-claude" ''
    set -euo pipefail
    cd "$HOME/.config/ha-mcp"
    exec claude "$@"
  '';
in {
  options.i4.ha-mcp.enable =
    lib.mkEnableOption "Home Assistant MCP server scoped to ~/.config/ha-mcp (and the ha-pi/ha-claude commands)";

  config = lib.mkIf cfg.enable (lib.warnIf (!haveCert) ''
    i4.ha-mcp: certs/wildcard-ec.crt is missing — add the *.ilma4.local cert (see certs/README.md).
    HTTPS to ${haUrl} will fail certificate verification until then.
  '' {
    home.packages = [
      pkgs-unstable.ha-mcp
      haMcpLauncher
      haPi
      haClaude
    ];

    # Both filenames so either agent finds it: Claude Code reads `.mcp.json`; pi MCP
    # packages / generic harnesses read `mcp.json`. Identical content.
    home.file.".config/ha-mcp/.mcp.json".text = mcpJson;
    home.file.".config/ha-mcp/mcp.json".text = mcpJson;
  });
}

{
  config,
  lib,
  pkgs,
  inputs,
  constants,
  myLib,
  ...
}: let
  cfg = config.i4.deploy;
  inherit (myLib.unifiedModules) isDarwin;
  repoUrl = "https://github.com/ilma4/nixos-config";
  rebuildCommand =
    if isDarwin
    then "/run/current-system/sw/bin/darwin-rebuild"
    else "nixos-rebuild";
  gitPackage = import ../lib/git-package.nix {inherit pkgs inputs;};
  updateInputs =
    [pkgs.coreutils gitPackage pkgs.openssh]
    ++ lib.optional (!isDarwin) pkgs.nixos-rebuild-ng
    ++ [config.nix.package];
  updateCommand = "/run/current-system/sw/bin/update-to-latest.sh";
  githubAllowedSigners = lib.concatMapStrings (key: "* " + key + "\n") constants.github-pub-keys;
  updateToLatest = pkgs.writeShellScriptBin "update-to-latest.sh" ''
    set -euo pipefail

    export PATH="${lib.makeBinPath updateInputs}:$PATH"
    export GIT_TERMINAL_PROMPT=0

    if [[ ''${EUID} -ne 0 ]]; then
      echo "Run this script with sudo: sudo update-to-latest.sh" >&2
      exit 1
    fi

    repo_url=${lib.escapeShellArg repoUrl}
    host_config=${lib.escapeShellArg cfg.flakeOutput}
    github_allowed_signers=${lib.escapeShellArg githubAllowedSigners}
    state_dir="/var/lib/i4-deploy"
    repo_dir="''${state_dir}/nixos-config"
    allowed_signers="$(mktemp)"

    cleanup() {
      rm -f "''${allowed_signers}"
    }
    trap cleanup EXIT

    mkdir -p "''${state_dir}"
    printf '%s' "''${github_allowed_signers}" >"''${allowed_signers}"
    chmod 0600 "''${allowed_signers}"

    if [[ ! -d "''${repo_dir}/.git" ]]; then
      rm -rf "''${repo_dir}"
      mkdir -p "''${repo_dir}"
      git -C "''${repo_dir}" init
      git -C "''${repo_dir}" remote add origin "''${repo_url}"
    fi

    git -C "''${repo_dir}" remote set-url origin "''${repo_url}"

    echo "Fetching latest commit from ''${repo_url}"
    git -C "''${repo_dir}" fetch --force --prune --depth=1 origin HEAD
    latest_commit="$(git -C "''${repo_dir}" rev-parse --verify 'FETCH_HEAD^{commit}')"

    has_ssh_signature=0
    while IFS= read -r line; do
      [[ -z "''${line}" ]] && break
      if [[ "''${line}" == "gpgsig -----BEGIN SSH SIGNATURE-----" ]]; then
        has_ssh_signature=1
        break
      fi
    done < <(git -C "''${repo_dir}" cat-file commit "''${latest_commit}")

    if [[ "''${has_ssh_signature}" -ne 1 ]]; then
      echo "Commit ''${latest_commit} is not signed with an SSH signature" >&2
      exit 1
    fi

    echo "Verifying commit ''${latest_commit} with configured GitHub public key"
    git -C "''${repo_dir}" \
      -c gpg.ssh.allowedSignersFile="''${allowed_signers}" \
      verify-commit "''${latest_commit}"

    echo "Checking out ''${latest_commit}"
    git -C "''${repo_dir}" checkout --force --detach "''${latest_commit}"
    git -C "''${repo_dir}" clean -fdx

    echo "Switching to ''${repo_dir}#''${host_config}"
    ${rebuildCommand} switch --flake "''${repo_dir}#''${host_config}"
  '';
in {
  options.i4.deploy = {
    enable = lib.mkEnableOption "the signed nixos-config self-update script";
    flakeOutput = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "The flake configuration to activate.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {environment.systemPackages = [updateToLatest];}
    (lib.optionalAttrs isDarwin {
      security.sudo.extraConfig = ''
        ${config.system.primaryUser} ALL=(root) NOPASSWD: ${updateCommand} ""
      '';
    })
    (lib.optionalAttrs (!isDarwin) {
      security.sudo.extraRules = lib.mkAfter [
        {
          users = ["ilma4"];
          commands = [
            {
              command = ''${lib.getExe updateToLatest} ""'';
              options = ["NOPASSWD"];
            }
            {
              command = ''${updateCommand} ""'';
              options = ["NOPASSWD"];
            }
          ];
        }
      ];
    })
  ]);
}

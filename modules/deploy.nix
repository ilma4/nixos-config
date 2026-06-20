{
  config,
  lib,
  pkgs,
  constants,
  ...
}: let
  cfg = config.i4.deploy;
  repoUrl = "https://github.com/ilma4/nixos-config";
  githubAllowedSigners = lib.concatMapStrings (key: "* " + key + "\n") constants.github-pub-keys;
  updateToLatest = pkgs.writeShellScriptBin "update-to-latest.sh" ''
    set -euo pipefail

    export PATH="${lib.makeBinPath [
      pkgs.coreutils
      pkgs.git
      pkgs.openssh
      pkgs.nixos-rebuild-ng
      config.nix.package
    ]}:$PATH"
    export GIT_TERMINAL_PROMPT=0

    if [[ ''${EUID} -ne 0 ]]; then
      echo "Run this script with sudo: sudo update-to-latest.sh" >&2
      exit 1
    fi

    repo_url=${lib.escapeShellArg repoUrl}
    host_config=${lib.escapeShellArg config.networking.hostName}
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
    nixos-rebuild switch --flake "''${repo_dir}#''${host_config}"
  '';
in {
  options.i4.deploy.enable = lib.mkEnableOption "the signed nixos-config self-update script";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [updateToLatest];

    security.sudo.extraRules = lib.mkAfter [
      {
        users = ["ilma4"];
        commands = [
          {
            command = ''${lib.getExe updateToLatest} ""'';
            options = ["NOPASSWD"];
          }
          {
            command = ''/run/current-system/sw/bin/update-to-latest.sh ""'';
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };
}

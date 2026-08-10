{
  config,
  lib,
  pkgs,
  constants,
  ...
}: let
  cfg = config.i4.initrd-ssh;
  keyPath = "/etc/secrets/initrd/ssh_host_ed25519_key";
  keyDirectory = builtins.dirOf keyPath;

  # Pure evaluation cannot see this variable. This is intended for the initial
  # installation, for example:
  # I4_DISABLE_INITRD_SSH=1 nixos-install --flake .#host --impure
  disabledForInstall = builtins.getEnv "I4_DISABLE_INITRD_SSH" == "1";
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # The first installation can omit initrd SSH because the host key does not
      # exist yet. Generate it on first boot so later rebuilds can enable SSH.
      systemd.services.generate-initrd-ssh-host-key = {
        description = "Generate the initrd SSH host key";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          if [[ ! -e ${lib.escapeShellArg keyPath} ]]; then
            ${pkgs.coreutils}/bin/install -d --mode=0700 ${lib.escapeShellArg keyDirectory}
            ${pkgs.openssh}/bin/ssh-keygen \
              -q \
              -t ed25519 \
              -N "" \
              -f ${lib.escapeShellArg keyPath}
          fi
        '';
      };
    }

    (lib.mkIf (!disabledForInstall) {
      boot.initrd.systemd.enable = lib.mkDefault true;
      boot.initrd.network.enable = lib.mkDefault true;

      boot.initrd.network.ssh = {
        enable = lib.mkDefault true;

        # Keep defaults aligned with previous `hosts/nas/nas.nix` setup.
        hostKeys = lib.mkDefault [keyPath];

        authorizedKeys = lib.mkDefault constants.main-pub-keys;

        # With UsePAM disabled (default in initrd), sshd prints /etc/motd
        # itself right before dropping to the shell. `lines` type, so this
        # concatenates with any host-specific extraConfig instead of clobbering it.
        extraConfig = "PrintMotd yes\n";
      };

      # Shown to anyone who SSHes into the initrd, printed by sshd (PrintMotd)
      # just before the interactive shell starts.
      boot.initrd.systemd.contents."/etc/motd".text = ''
        run systemd-tty-ask-password-agent to unlock encrypted drive
      '';
    })
  ]);
}

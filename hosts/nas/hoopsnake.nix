# hoopsnake: a tiny SSH server that joins the tailnet from within the initrd,
# letting us unlock the LUKS-encrypted root over Tailscale at boot time
# (https://github.com/boinkor-net/hoopsnake).
#
# This complements the existing LAN initrd SSH server (`i4.initrd-ssh.enable`):
# that one stays reachable on the local network, while hoopsnake lets us unlock
# remotely without exposing initrd SSH to the LAN/internet.
{
  config,
  lib,
  pkgs,
  inputs,
  constants,
  ...
}: let
  # Same admins as the regular system / LAN initrd unlock. Public keys, so a
  # store path is fine here.
  authorizedKeys =
    pkgs.writeText "hoopsnake-authorized-keys"
    (lib.concatStringsSep "\n" constants.main-pub-keys + "\n");
in {
  imports = [inputs.hoopsnake.nixosModules.default];

  # hoopsnake needs systemd + networking in the initrd. nas already enables both
  # through `i4.initrd-ssh.enable`; restate them so this module is self-contained.
  boot.initrd.systemd.enable = true;
  boot.initrd.network.enable = true;

  # Secrets consumed by hoopsnake in the initrd. The hoopsnake module copies the
  # `*.file` credential paths below into `boot.initrd.secrets`, which embeds them
  # into the initramfs at `nixos-rebuild switch` time (sops decrypts to
  # /run/secrets during activation, before the bootloader appends initrd secrets).
  #
  # NOTE: these end up in plaintext inside the initramfs on the unencrypted /boot
  # partition - an accepted limitation of initrd SSH unlocking. Populate them with
  # ./hoopsnake-create-secrets.sh.
  sops.secrets = {
    "hoopsnake/host_key" = {};
    "hoopsnake/tailscale_client_id" = {};
    "hoopsnake/tailscale_client_secret" = {};
  };

  # The interactive systemd password agent is not in the initrd by default; add it
  # so the hoopsnake session can answer the LUKS passphrase prompt.
  boot.initrd.systemd.extraBin.systemd-tty-ask-password-agent = "${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent";

  boot.initrd.network.hoopsnake = {
    enable = true;

    ssh = {
      authorizedKeysFile = authorizedKeys;
      # On connect, drive the password agent so you can type the LUKS passphrase
      # and continue booting. The session ends by itself once boot proceeds
      # (initrd switch-root tears hoopsnake down).
      commandLine = ["/bin/systemd-tty-ask-password-agent" "--watch"];
    };

    # systemd-in-initrd uses systemd credentials (not the scripted-stage1
    # environmentFile). encrypted = false because no TPM/host key is available
    # this early to decrypt systemd-creds; the files are plaintext sops secrets.
    systemd-credentials = {
      privateHostKey = {
        file = config.sops.secrets."hoopsnake/host_key".path;
        encrypted = false;
      };
      # Tailscale OAuth client (non-expiring, unlike auth keys). hoopsnake uses it
      # to mint an ephemeral, tagged auth key on each boot.
      clientId = {
        file = config.sops.secrets."hoopsnake/tailscale_client_id".path;
        encrypted = false;
      };
      clientSecret = {
        file = config.sops.secrets."hoopsnake/tailscale_client_secret".path;
        encrypted = false;
      };
    };

    tailscale = {
      name = "nas-boot";
      tags = ["tag:hoopsnake"];
      # Auto-approve the boot node. The OAuth client + tag ACL must permit this.
      preauthorized = true;
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  brewPrefix = config.homebrew.prefix or (lib.removeSuffix "/bin" config.homebrew.brewPrefix);
  brew = "${brewPrefix}/bin/brew";
in {
  config = lib.mkIf config.homebrew.enable {
    launchd.user.agents.homebrew-auto-upgrade = {
      path = [pkgs.bash brewPrefix pkgs.coreutils];

      script = ''
        set -euo pipefail

        echo "''$(date): running autoupdate"

        # Refresh metadata
        ${brew} update

        # Upgrade formulae
        ${brew} upgrade

        # Upgrade casks too, including auto-updating/version:latest ones
        ${brew} upgrade --cask --greedy

        # Remove old versions/cache
        ${brew} cleanup --prune=all
      '';

      serviceConfig = {
        Label = "org.nixos.homebrew-auto-upgrade";
        RunAtLoad = true;
        StartInterval = 43200;
        StandardOutPath = "/tmp/homebrew-auto-upgrade.log";
        StandardErrorPath = "/tmp/homebrew-auto-upgrade.err.log";
        ProcessType = "Background";
      };
    };
  };
}

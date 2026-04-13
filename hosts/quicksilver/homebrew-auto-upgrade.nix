{
  config,
  lib,
  pkgs,
  ...
}: let
  brewPrefix = config.homebrew.prefix or (lib.removeSuffix "/bin" config.homebrew.brewPrefix);
in {
  config = lib.mkIf config.homebrew.enable {
    launchd.user.agents.homebrew-auto-upgrade = {
      path = [pkgs.bash brewPrefix pkgs.coreutils];

      script = ''
        set -euo pipefail

        echo "''$(date): running autoupdate"

        # Refresh metadata
        /opt/homebrew/bin/brew update

        # Upgrade formulae
        /opt/homebrew/bin/brew upgrade

        # Upgrade casks too, including auto-updating/version:latest ones
        /opt/homebrew/bin/brew upgrade --cask --greedy

        # Remove old versions/cache
        /opt/homebrew/bin/brew cleanup --prune=all
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

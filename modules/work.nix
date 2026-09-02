{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {
    i4.work = {
      enable-gui-apps = lib.mkEnableOption "Enable GUI apps";
      enable = lib.mkEnableOption "configure for work";
    };
  };

  config = lib.mkIf config.i4.work.enable {
    home.packages = [pkgs.watchman];

    xdg.configFile."jj/conf.d/30-fsmonitor.toml".text = ''
      [fsmonitor]
      backend = "watchman"

      [fsmonitor.watchman]
      register-snapshot-trigger = true
    '';

    # Use the 1Password SSH agent by default on the work account.
    programs.ssh.settings = {
      "*" = {
        IdentityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
      };
    };

    programs.git.settings.user = {
      name = "Ilia Malakhov";
      email = "ilia.malakhov@jetbrains.com";
    };
  };
}

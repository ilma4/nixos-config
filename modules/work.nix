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
    # Use the 1Password SSH agent by default on the work account.
    programs.ssh.matchBlocks = {
      "*" = {
        identityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
      };
    };

    home.packages = with pkgs; [
      bun
    ];

    programs.git.settings.user = {
      name = "Ilia Malakhov";
      email = "ilia.malakhov@jetbrains.com";
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    i4.work = {
      enable-gui-apps = lib.mkEnableOption "Enable GUI apps";
      enable = lib.mkEnableOption "configure for work";
    };
  };

  config = lib.mkIf config.i4.work.enable {
    # use ssh key from 1password for jetbrains git
    programs.ssh.matchBlocks = {
      "git.jetbrains.team" = {
        extraOptions = {
          "IdentityAgent" = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""; # 1password ssh-agent
        };
      };
    };

    # use jetbrains email for work repos
    programs.git = {
      includes = [
        {
          contents.user.email = "ilia.malakhov@jetbrains.com";
          condition = "gitdir:~/Projects/JetBrains/";
        }
      ];
    };
  };
}

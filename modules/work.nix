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
    # use ssh key from 1password for jetbrains git
    programs.ssh.matchBlocks = {
      "git.jetbrains.team" = {
        extraOptions = {
          "IdentityAgent" = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""; # 1password ssh-agent
        };
      };
    };

    home.packages = with pkgs; [
      bun
    ];

    # use jetbrains email for work repos
    programs.git = {
      includes = [
        {
          contents = {
            user.email = "ilia.malakhov@jetbrains.com";
            # commit.gpgsign = false;
            # user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHPP96JkvAFJRI9V08kNz7ah6CfPsRV08DRzu8wjk+4I";
          };
          condition = "gitdir:~/Projects/JetBrains/";
        }
      ];
    };
  };
}

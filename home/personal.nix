{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    screen
  ];
  programs.ssh.extraConfig =
        ''
          IdentityFile ~/.ssh/github
          ''
        + (
          if pkgs.stdenv.isDarwin
          then "UseKeychain yes"
          else ""
        );
}

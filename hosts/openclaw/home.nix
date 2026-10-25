{...}: {
  imports = [../../home/base.nix];

  home.username = "ilma4";
  home.file.".openclaw/skills/mail-archive".source = ../../dotfiles/openclaw/skills/mail-archive;
}

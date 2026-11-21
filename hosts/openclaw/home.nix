{...}: {
  imports = [../../home/base.nix];

  i4.revision.enable = false;
  home.username = "ilma4";
  home.file.".openclaw/skills/mail-archive".source = ../../dotfiles/openclaw/skills/mail-archive;
}

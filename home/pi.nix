{
  lib,
  pkgs,
  ...
}: {
  # home.file.".pi/agent/models.json".source = ../hosts/quicksilver/pi/models.json;
  home.file.".pi/agent/extensions/notify-finish.ts".source = ../dotfiles/pi/extensions/notify-finish.ts;
  home.file.".pi/agent/extensions/compaction-count.ts".source = ../dotfiles/pi/extensions/compaction-count.ts;
}

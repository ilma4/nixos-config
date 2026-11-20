{
  imports = [./universall-apps.nix];

  i4.apps.apps = {
    steam = {};
    heroic = {linuxInstallation = "package";}; # GOG / Epic Games launcher
    prismlauncher = {linuxInstallation = "package";}; # Minecraft launcher
    dolphin-emu = {linuxInstallation = "package";}; # Wii emulator
  };
}

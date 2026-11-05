{config, ...}: let
  mediaPath = "/srv/jellyfin/ymfah";
in {
  services.jellyfin.enable = true;

  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = ["/home/ilma4/NoBackup/ymfah"];
    serviceConfig = {
      # Expose only the videos inside the service's mount namespace, bypassing
      # the private home directory without changing its permissions.
      ProtectHome = "tmpfs";
      BindReadOnlyPaths = ["/home/ilma4/NoBackup/ymfah:${mediaPath}"];
    };

    # Seed Jellyfin's native library files before its first scan. Leave library
    # options writable so later changes in the dashboard persist.
    preStart = ''
      set -euo pipefail
      libraryDir="${config.services.jellyfin.dataDir}/root/default/ymfah"
      mkdir -p "$libraryDir"
      # Jellyfin reads the entire shortcut verbatim, including any newline.
      printf '%s' '${mediaPath}' > "$libraryDir/ymfah.mblink"
      if [ ! -e "$libraryDir/options.xml" ]; then
        cat > "$libraryDir/options.xml" <<'XML'
      <?xml version="1.0" encoding="utf-8"?>
      <LibraryOptions>
        <Enabled>true</Enabled>
        <EnablePhotos>false</EnablePhotos>
        <EnableRealtimeMonitor>true</EnableRealtimeMonitor>
        <SaveLocalMetadata>false</SaveLocalMetadata>
        <SaveSubtitlesWithMedia>false</SaveSubtitlesWithMedia>
        <PathInfos>
          <MediaPathInfo>
            <Path>${mediaPath}</Path>
          </MediaPathInfo>
        </PathInfos>
      </LibraryOptions>
      XML
      fi
    '';
  };

  # Match the existing SMB share's LAN-only access policy. Jellyfin uses HTTP
  # on TCP 8096 and client discovery on UDP 7359.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.0/24 --dport 8096 -j nixos-fw-accept
    iptables -A nixos-fw -p udp -s 192.168.1.0/24 --dport 7359 -j nixos-fw-accept
  '';
}

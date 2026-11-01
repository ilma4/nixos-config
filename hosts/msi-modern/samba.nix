{
  services.samba = {
    enable = true;
    openFirewall = false;
    nmbd.enable = false;
    winbindd.enable = false;

    settings = {
      global = {
        security = "user";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "hosts allow" = "127.0.0.1 ::1 192.168.1.0/24";
        "hosts deny" = "ALL";
        "smb ports" = "445";
      };

      ymfah = {
        path = "/home/ilma4/NoBackup/ymfah";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "guest only" = "yes";
        # Read with the owner's permissions without changing filesystem access.
        "force user" = "ilma4";
      };
    };
  };

  # Open direct SMB only to the local IPv4 subnet.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.0/24 --dport 445 -j nixos-fw-accept
  '';
}

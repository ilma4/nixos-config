{
  services.samba = {
    enable = true;
    openFirewall = true; # Automatically opens ports 139/445 (and others if needed)

    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "My NixOS Server";
        "netbios name" = "NIXOS-SERVER"; # Optional: customize your server's name
        "security" = "user";
        "guest account" = "nobody";
        "map to guest" = "bad user"; # Allows guest access on failed login

        # Restrict access to local network only (prevents external access)
        "hosts allow" = "127.0.0.1 ::1 192.168.1.0/24 10.0.0.0/8 172.16.0.0/12";
      };

      # This is the share name (e.g., \\your-ip\myreadonlyshare)
      ilma4-ro-share = {
        path = "/mnt/hdd/ilma4"; # Replace with your actual directory
        "browseable" = "yes";
        "read only" = "yes"; # Enforces read-only
        "guest ok" = "yes"; # Allows anonymous access
        "comment" = "Read-only public share";
        # Optional: force all access as a specific user for permission consistency
        # "force user" = "yourunixuser";  # Must exist as a system user
      };

      # This is the share name (e.g., \\your-ip\myreadonlyshare)
      ilma4-rw-share = {
        path = "/mnt/hdd/ilma4"; # Replace with your actual directory
        "browseable" = "yes";
        "read only" = "no";
        "writable" = "yes";
        "guest ok" = "no";
        "valid users" = "ilma4";
        "comment" = "Writable share";

        # Restrict access to local network only (prevents external access)
        "hosts allow" = "127.0.0.1 ::1 192.168.1.0/24 10.0.0.0/8 172.16.0.0/12";
        # Optional: force all access as a specific user for permission consistency
        "force user" = "ilma4";
      };
    };
  };

  # Optional: For better Windows discovery (shows up in Network)
  services.samba-wsdd.enable = true; # Web Service Discovery (modern alternative to NetBIOS)
}

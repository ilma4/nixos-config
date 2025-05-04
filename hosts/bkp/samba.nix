{
  services.samba = {
    enable = true;
    openFirewall = true;
  };
  services.samba.settings = {
    public = {
      path = "/run/media/ilma4/f86b7490-3309-44ad-876a-50a8578012b0";
      "read only" = true;
      browserable = "yes";
      "guest ok" = "yes";
      comment = "Public read-only share";
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
    discovery = true;
  };
}

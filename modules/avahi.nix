{
  config,
  lib,
  myLib,
  ...
}: let
  cfg = config.i4.avahi;
in {
  options.i4.avahi = {
    enable = lib.mkEnableOption "Avahi service for .local domain resolution";
  };

  config = lib.mkIf cfg.enable (myLib.unifiedModules.enableForConfigurations ["isNixos"] {
    # Enable avahi server. Machine will be avaliable by address 'hostname.local'
    services.avahi = {
      openFirewall = true;
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      ipv6 = true;
      publish = {
        enable = true;
        domain = true;
        addresses = true;
      };
      reflector = true;
    };
  });
}

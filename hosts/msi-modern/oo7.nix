{
  config,
  pkgs,
  pkgs-unstable,
  ...
}: let
  # The pinned stable release ships oo7 without PAM integration.
  inherit (pkgs-unstable) oo7 oo7-pam oo7-portal oo7-server;
  pamModule = "${oo7-pam}/lib/security/pam_oo7.so";
  loginRules = config.security.pam.services.login.rules;
in {
  services.gnome.gnome-keyring.enable = false;
  environment.systemPackages = [oo7];

  # Start at login for the PAM handoff, and allow clients to activate it again
  # via D-Bus if it is stopped. The packaged daemon has no D-Bus service file.
  services.dbus.packages = [
    (pkgs.writeTextDir "share/dbus-1/services/org.freedesktop.secrets.service" ''
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=/bin/false
      SystemdService=oo7-daemon.service
    '')
  ];
  systemd.packages = [oo7-server];
  systemd.user.services.oo7-daemon = {
    wantedBy = ["default.target"];
    serviceConfig = {
      # Keep the upstream sandbox (including NoNewPrivileges) and prevent
      # swapping the daemon's memory without giving it a privileged wrapper.
      ExecStart = ["" "${oo7-server}/libexec/oo7-daemon"];
      MemorySwapMax = 0;
    };
  };

  # Sway starts from a password-authenticated TTY login. As in NixOS's
  # upstream oo7 integration, capture PAM_AUTHTOK before pam_unix's
  # sufficient rule can short-circuit; only the normal stack grants access.
  security.pam.services.login.rules = {
    auth.oo7-unix-early = {
      inherit (loginRules.auth.unix) enable modulePath settings;
      control = "optional";
      order = loginRules.auth.unix.order - 20;
    };
    auth.oo7 = {
      control = "optional";
      modulePath = pamModule;
      order = loginRules.auth.unix.order - 10;
    };
    session.oo7 = {
      control = "optional";
      modulePath = pamModule;
      order = loginRules.session.systemd.order + 10;
      settings.auto_start = true;
    };
  };

  # Select oo7 only for the Secret portal; keep Sway's other backends intact.
  xdg.portal = {
    extraPortals = [oo7-portal];
    config.sway."org.freedesktop.impl.portal.Secret" = "oo7-portal";
  };
  systemd.user.services.oo7-portal.aliases = ["dbus-org.freedesktop.impl.portal.desktop.oo7.service"];
}

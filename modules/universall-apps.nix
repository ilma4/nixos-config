{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkOption;
  inherit (lib.unifiedModules.checkers) isLinux isDarwin isHome;
in {
  options = {
    i4-apps = {
      apps = {
        type = types.attrsOf (types.submodule (name: {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };
            linuxName = mkOption {
              type = types.str;
              default = name;
            };
            macName = mkOption {
              type = types.str;
              default = name;
            };
            linuxInstallation = mkOption {
              type = types.nullOr (
                types.enum [
                  "programm"
                  "package"
                ]
              );
              default = "programm";
            };
            macInstallation = mkOption {
              type = types.nullOr (
                types.enum [
                  "cask"
                  "brew"
                  "package"
                ]
              );
              default = "cask";
            };
          };
        }));
      };
    };
    enable = mkOption {
      type = types.bool;
      default = true;
    };
  };
  config = lib.mkIf config.i4-apps.enable (let
    packageList = lib.concatMap (
      app:
        if app.enable && ((isLinux && app.linuxInstallation == "package") || (isDarwin && app.macInstallation == "package"))
        then let
          pkgName =
            if isLinux
            then app.linuxName
            else app.macName;
        in [(lib.getAttr pkgName pkgs)]
        else []
    ) (lib.attrValues config.i4-apps.apps);
  in {
    programs = lib.mkIf isLinux (lib.mkMerge (lib.mapAttrsToList (
        _: app:
          lib.mkIf (app.enable && app.linuxInstallation == "programm") {
            ${app.linuxName}.enable = true;
          }
      )
      config.i4-apps.apps));

    homebrew = lib.mkIf isDarwin {
      casks = lib.concatMap (
        app:
          if app.enable && app.macInstallation == "cask"
          then [app.macName]
          else []
      ) (lib.attrValues config.i4-apps.apps);
      brews = lib.concatMap (
        app:
          if app.enable && app.macInstallation == "brew"
          then [app.macName]
          else []
      ) (lib.attrValues config.i4-apps.apps);
    };

    environment.systemPackages = lib.mkIf (!isHome) packageList;
    home.packages = lib.mkIf isHome packageList;
  });
}

{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  inherit (myLib.unifiedModules.checkers) isDarwin isHomeManager isLinux;

  appType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      linuxName = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      macName = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      linuxInstallation = mkOption {
        type = types.nullOr (types.enum ["program" "package"]);
        default = "program";
      };
      macInstallation = mkOption {
        type = types.nullOr (types.enum ["cask" "brew" "package"]);
        default = "cask";
      };
    };
  };
in {
  options.i4.apps = {
    apps = mkOption {
      type = types.attrsOf appType;
      default = {};
    };

    enable = mkEnableOption "Enable my apps";
  };

  config = mkIf config.i4.apps.enable (
    let
      appsFixedNames =
        lib.mapAttrs (
          name: app:
            app
            // (
              if app.macName == null
              then {macName = name;}
              else {}
            )
            // (
              if app.linuxName == null
              then {linuxName = name;}
              else {}
            )
        )
        config.i4.apps.apps;

      enabledApps = lib.mapAttrsToList (_: app: app) (lib.filterAttrs (_: app: app.enable) appsFixedNames);

      linuxProgramNames = map (app: app.linuxName) (lib.filter (app: app.linuxInstallation == "program") enabledApps);

      linuxPackageNames = map (app: app.linuxName) (lib.filter (app: app.linuxInstallation == "package") enabledApps);

      macCaskNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "cask") enabledApps);

      macBrewNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "brew") enabledApps);

      macPackageNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "package") enabledApps);

      packageNames =
        if isLinux
        then linuxPackageNames
        else macPackageNames;

      packageList = map (name: pkgs.${name}) packageNames;
    in
      lib.optionalAttrs (!isHomeManager) {
        environment.systemPackages = packageList;
      }
      // lib.optionalAttrs isHomeManager {
        home.packages = packageList;
      }
      // lib.optionalAttrs isLinux {
        programs = mkMerge (map (name: {${name}.enable = true;}) linuxProgramNames);
      }
      // lib.optionalAttrs isDarwin {
        homebrew = {
          casks = macCaskNames;
          brews = macBrewNames;
        };
      }
  );
}

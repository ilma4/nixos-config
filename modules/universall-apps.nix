{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  inherit (myLib.unifiedModules.checkers) isDarwin isHomeManager isLinux;

  appType = types.submodule (name: {
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
            "program"
            "package"
          ]
        );
        default = "program";
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
  });
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
      enabledApps = lib.mapAttrsToList (_: app: app) (lib.filterAttrs (_: app: app.enable) config.i4.apps.apps);

      linuxProgramNames = map (app: app.linuxName) (lib.filter (app: app.linuxInstallation == "program") enabledApps);

      linuxPackageNames = map (app: app.linuxName) (lib.filter (app: app.linuxInstallation == "package") enabledApps);

      macCaskNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "cask") enabledApps);

      macBrewNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "brew") enabledApps);

      macPackageNames = map (app: app.name) (lib.filter (app: app.macInstallation == "package") enabledApps);

      packageList =
        if isLinux
        then linuxPackageNames
        else macPackageNames;
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

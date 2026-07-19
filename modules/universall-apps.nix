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
      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Package to use when the app is installed as a package";
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

      packageAssertions = lib.mapAttrsToList (name: app: {
        assertion = app.package == null || app.linuxInstallation == "package" || app.macInstallation == "package";
        message = "i4.apps.apps.${name}.package can only be set when linuxInstallation or macInstallation is package";
      }) appsFixedNames;

      enabledApps = lib.mapAttrsToList (_: app: app) (lib.filterAttrs (_: app: app.enable) appsFixedNames);

      linuxProgramNames = map (app: app.linuxName) (lib.filter (app: app.linuxInstallation == "program") enabledApps);

      macCaskNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "cask") enabledApps);

      macBrewNames = map (app: app.macName) (lib.filter (app: app.macInstallation == "brew") enabledApps);

      packageApps = lib.filter (
        app:
          (isLinux && app.linuxInstallation == "package")
          || (isDarwin && app.macInstallation == "package")
      ) enabledApps;

      packageList = map (
        app:
          if app.package != null
          then app.package
          else pkgs.${
            if isLinux
            then app.linuxName
            else app.macName
          }
      ) packageApps;
    in
      {
        assertions = packageAssertions;
      }
      // lib.optionalAttrs (!isHomeManager) {
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

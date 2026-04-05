{
  config,
  lib,
  myLib,
  pkgs,
  ...
}: let
  inherit (lib) types mkOption;
  inherit (myLib.unifiedModules.checkers) isLinux isDarwin isHomeManager;
  getLinuxName = name: app:
    if app.linuxName != null
    then app.linuxName
    else name;
in {
  options = {
    i4.apps = {
      apps = mkOption {
        type = types.attrsOf (types.submodule (name: {
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
        }));
        default = {};
      };

      enable = lib.mkEnableOption "Enable my apps";
    };
  };

  # universall module
  config = lib.mkIf config.i4.apps.enable (
    let
      linuxPackageAssertions =
        lib.mapAttrsToList (name: app: let
          linuxName = getLinuxName name app;
        in {
          assertion =
            !(
              isLinux
              && app.enable
              && app.linuxInstallation == "package"
            )
            || lib.hasAttrByPath [linuxName] pkgs;
          message = "i4.apps.apps.${name}: resolved Linux package `${linuxName}` is missing from pkgs";
        })
        config.i4.apps.apps;

      packageList = lib.concatLists (
        lib.mapAttrsToList (
          name: app: let
            linuxName = getLinuxName name app;
          in
            if !(app.enable && ((isLinux && app.linuxInstallation == "package") || (isDarwin && app.macInstallation == "package")))
            then []
            else if isLinux
            then
              lib.optionals (lib.hasAttrByPath [linuxName] pkgs) [
                (lib.getAttrFromPath [linuxName] pkgs)
              ]
            else [(lib.getAttr name pkgs)]
        )
        config.i4.apps.apps
      );
    in
      {
        assertions = linuxPackageAssertions;
      }
      // lib.optionalAttrs (!isHomeManager) {
        environment.systemPackages = packageList;
      }
      // lib.optionalAttrs isHomeManager {
        home.packages = packageList;
      }
      // lib.optionalAttrs (!isDarwin) {
        programs = lib.mkIf isLinux (lib.mkMerge (lib.mapAttrsToList (
            name: app:
              lib.mkIf (app.enable && app.linuxInstallation == "program")
              (lib.setAttrByPath [(getLinuxName name app) "enable"] true)
          )
          config.i4.apps.apps));
      }
      // lib.optionalAttrs isDarwin {
        homebrew = lib.mkIf isDarwin {
          casks = lib.concatLists (
            lib.mapAttrsToList (
              name: app:
                if app.enable && app.macInstallation == "cask"
                then [
                  (
                    if app.macName != null
                    then app.macName
                    else name
                  )
                ]
                else []
            )
            config.i4.apps.apps
          );
          brews = lib.concatLists (
            lib.mapAttrsToList (
              name: app:
                if app.enable && app.macInstallation == "brew"
                then [
                  (
                    if app.macName != null
                    then app.macName
                    else name
                  )
                ]
                else []
            )
            config.i4.apps.apps
          );
        };
      }
  );
}

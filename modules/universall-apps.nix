{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkOption;
  inherit (lib.unifiedModules.checkers) isLinux isDarwin isHomeManager;
in {
  options = {
    i4-apps = {
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

      enable = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  # universall module
  config = lib.mkIf config.i4-apps.enable (
    let
      packageList = lib.concatLists (
        lib.mapAttrsToList (
          name: app:
            if app.enable && ((isLinux && app.linuxInstallation == "package") || (isDarwin && app.macInstallation == "package"))
            then [
              (lib.getAttr name pkgs)
            ]
            else []
        )
        config.i4-apps.apps
      );
    in
      {}
      // lib.optionalAttrs (!isHomeManager) {
        environment.systemPackages = packageList;
      }
      // lib.optionalAttrs isHomeManager {
        home.packages = packageList;
      }
      // lib.optionalAttrs (!isDarwin) {
        programs = lib.mkIf isLinux (lib.mkMerge (lib.mapAttrsToList (
            name: app:
              lib.mkIf (app.enable && app.linuxInstallation == "program") {
                ${name}.enable = true;
              }
          )
          config.i4-apps.apps));
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
            config.i4-apps.apps
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
            config.i4-apps.apps
          );
        };
      }
  );
}

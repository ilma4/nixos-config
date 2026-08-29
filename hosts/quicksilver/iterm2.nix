{
  config,
  lib,
  ...
}: let
  replaceHome = value:
    if builtins.isString value
    then builtins.replaceStrings ["@HOME@"] [config.home.homeDirectory] value
    else if builtins.isList value
    then map replaceHome value
    else if builtins.isAttrs value
    then lib.mapAttrs (_: replaceHome) value
    else value;

  preferences = builtins.fromJSON (builtins.readFile ../../dotfiles/iterm2/preferences.json);
in {
  targets.darwin.defaults."com.googlecode.iterm2" = replaceHome preferences;
}

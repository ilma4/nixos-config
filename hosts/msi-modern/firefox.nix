{lib, ...}: let
  # Firefox add-on IDs mapped to their Mozilla Add-ons slugs.
  extensions = {
    "clipper@obsidian.md" = "web-clipper-obsidian";
    "addon@darkreader.org" = "darkreader";
    "vimium-c@gdh1995.cn" = "vimium-c";
    "harper@writewithharper.com" = "private-grammar-checker-harper";
    "sponsorBlocker@ajay.app" = "sponsorblock";
    "amptra@keepa.com" = "keepa";
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
    "enhancerforyoutube@maximerf.addons.mozilla.org" = "enhancer-for-youtube";
    "uBlock0@raymondhill.net" = "ublock-origin";
  };
in {
  programs.firefox.policies.ExtensionSettings = lib.mapAttrs (_: slug: {
    installation_mode = "normal_installed";
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
  }) extensions;
}

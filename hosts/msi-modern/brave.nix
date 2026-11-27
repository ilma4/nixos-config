{lib, ...}: let
  webStoreExtensions = [
    "cnjifjpddelmedmihgijeibhnjfabmlf" # Obsidian Web Clipper
    "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
    "hfjbmagddngcpeloejdejnfgbamkjaeg" # Vimium C
    "lodbfhdipoipcjmlebjbgmmgekckhpfb" # Harper
    "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock
    "neebplgakaahbhdphmkckjjcegoiijjo" # Keepa
    "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
    "ponfpcnoihfmfllpaingbgckeeldkhle" # Enhancer for YouTube
  ];
in {
  environment.etc."brave/policies/managed/brave.json".text = builtins.toJSON {
    SpellcheckEnabled = true;
    SpellcheckLanguage = ["en-US" "ru"];
    SpellCheckServiceEnabled = false;

    ExtensionSettings =
      lib.genAttrs webStoreExtensions (_: {
        installation_mode = "normal_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
      })
      // {
        # The upstream signed GitHub build has a different ID from Brave's build.
        "fkgkibajhfbepljeaefdnfnegdcjomkh" = {
          installation_mode = "normal_installed";
          update_url = "https://raw.githubusercontent.com/gorhill/uBlock/master/dist/chromium/update.xml";
          override_update_url = true;
        };
      };
  };
}

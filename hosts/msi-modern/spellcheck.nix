{pkgs, ...}: let
  # Match Sway's US English and Russian keyboard layouts.
  dictionaries = with pkgs.hunspellDicts; {inherit en_US ru_RU;};
  hunspell = pkgs.hunspell.withDicts (_: builtins.attrValues dictionaries);
in {
  programs.firefox = {
    preferences = {
      # Check single-line inputs as well as multiline fields.
      "layout.spellcheckDefault" = 2;
      "spellchecker.dictionary_path" = "${hunspell}/share/hunspell";
    };
    policies.ExtensionSettings."harper@writewithharper.com" = {
      installation_mode = "normal_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/private-grammar-checker-harper/latest.xpi";
    };
  };

  environment.etc."brave/policies/managed/spellcheck.json".text = builtins.toJSON {
    SpellcheckEnabled = true;
    SpellcheckLanguage = ["en-US" "ru"];
    SpellCheckServiceEnabled = false;
    ExtensionSettings."lodbfhdipoipcjmlebjbgmmgekckhpfb" = {
      installation_mode = "normal_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
  };

  home-manager.users.ilma4 = {
    config,
    lib,
    ...
  }: let
    telegramDictionaries = "${config.xdg.dataHome}/TelegramDesktop/tdata/dictionaries";
  in {
    home.packages = [hunspell];

    programs.zed-editor.extraPackages = with pkgs; [harper codebook];
    i4.zed.extraSettings.auto_install_extensions = {
      harper = true;
      codebook = true; # Uses Hunspell-format dictionaries via Spellbook.
    };
    xdg.configFile."codebook/codebook.toml".text = ''
      dictionaries = ["en_us", "ru"]
    '';

    # Telegram uses its own Hunspell cache rather than the system search path.
    # Seed it without overwriting dictionaries the app already downloaded.
    home.activation.seedTelegramDictionaries = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [[ -d ${lib.escapeShellArg (builtins.dirOf telegramDictionaries)} ]]; then
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (locale: dictionary: let
          target = lib.escapeShellArg "${telegramDictionaries}/${locale}";
        in ''
          run mkdir -p -- ${target}
          run cp --update=none -- ${dictionary}/share/hunspell/${locale}.{aff,dic} ${target}/
        '')
        dictionaries)}
      fi
    '';
  };
}

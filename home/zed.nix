{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.zed;
  isDarwin = pkgs.stdenv.isDarwin;
  # `i4.dev.nix` lives in ./dev.nix, which is not guaranteed to be imported.
  nixToolsEnabled = lib.attrByPath ["i4" "dev" "nix" "enable"] false config;

  # Language servers that are intentionally not installed on Darwin (macOS).
  linuxOnlyLanguageServers = with pkgs; [
    basedpyright
    docker-language-server
    package-version-server
    sourcekit-lsp
    texlab
  ];

  nixLanguageServers = with pkgs; [
    nil
    nixd
  ];

  languageServers = with pkgs;
    [
      nodejs # zed might need node and npm anyway

      bash-language-server
      # jdt-language-server
      # kotlin-lsp # TODO uncomment when added to nixpkgs
      # kotlin-language-server # do not add, obsolete. Use `kotlin-lsp` instead
      markdown-oxide
      ruff
      rust-analyzer
      taplo
      typescript-go
      vscode-langservers-extracted
      yaml-language-server
    ]
    ++ lib.optionals (!isDarwin) linuxOnlyLanguageServers
    ++ lib.optionals nixToolsEnabled nixLanguageServers;

  # Language servers this host does not install. Zed downloads the binary of the
  # extension's language server unless it is already in PATH, so extensions that
  # would pull one of these are skipped from `auto_install_extensions`.
  missingLanguageServers = with pkgs;
    lib.optionals isDarwin linuxOnlyLanguageServers
    ++ lib.optionals (!nixToolsEnabled) nixLanguageServers;
  extensionsByLanguageServer = {
    docker-language-server = ["dockerfile" "docker-compose"];
    nil = ["nix"];
    nixd = ["nix"];
    sourcekit-lsp = ["swift"];
    texlab = ["latex"];
  };
  blacklistedExtensions = lib.unique (
    lib.concatMap (server: extensionsByLanguageServer.${lib.getName server} or []) missingLanguageServers
  );

  # The dotfile holds everything that works without extra tooling; settings that
  # depend on Nix tooling are only merged in when it is actually installed, so
  # Zed never tries to download nil/nixd or run a missing formatter.
  baseSettings = builtins.fromJSON (builtins.readFile ../dotfiles/zed/settings.json);
  nixToolingSettings = {
    languages.Nix.formatter.external = {
      command = "alejandra";
      arguments = ["--quiet" "--"];
    };
    lsp = {
      nil.settings = {
        diagnostics.ignored = ["unused_binding"];
        nix.flake.autoArchive = true;
      };
      nixd.settings.diagnostic.suppress = ["sema-extra-with"];
    };
  };
  settingsJson = let
    merged =
      if nixToolsEnabled
      then lib.recursiveUpdate baseSettings nixToolingSettings
      else baseSettings;
    # Plain `//` (not recursiveUpdate) so removed keys really disappear.
    autoInstallExtensions =
      lib.filterAttrs (name: _: !builtins.elem name blacklistedExtensions)
      (merged.auto_install_extensions or {});
  in
    merged // {auto_install_extensions = autoInstallExtensions;};
  # The rest of dotfiles/zed (keymap, themes, prompts) is copied verbatim.
  zedConfigDir = pkgs.runCommandLocal "zed-config" {} ''
    set -euo pipefail
    mkdir -p $out
    cp -R ${../dotfiles/zed}/. $out/
    chmod -R u+w $out
    rm -f $out/settings.json
    cp ${pkgs.writeText "zed-settings.json" (builtins.toJSON settingsJson)} $out/settings.json
  '';
in {
  options.i4.zed = {
    enable = lib.mkEnableOption "Zed editor configuration";
  };

  config = lib.mkIf cfg.enable {
    # Zed prefers language servers found in PATH over downloading its own.
    # The Linux package is wrapped with this PATH; Homebrew Zed on Darwin
    # discovers the same binaries through the Home Manager profile.
    home.packages = lib.optionals isDarwin languageServers;

    programs.zed-editor = {
      enable = !isDarwin;
      extraPackages = languageServers;
    };

    home.file.".config/zed".source = zedConfigDir;
  };
}

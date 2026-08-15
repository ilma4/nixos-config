{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.zed;
  isDarwin = pkgs.stdenv.isDarwin;
  languageServers = with pkgs; [
    nodejs # zed might need node and npm anyway

    bash-language-server
    basedpyright
    docker-language-server
    # kotlin-lsp # TODO uncomment when added to nixpkgs
    # kotlin-language-server # do not add, obsolete. Use `kotlin-lsp` instead
    markdown-oxide
    nil
    nixd
    package-version-server
    ruff
    rust-analyzer
    sourcekit-lsp
    taplo
    texlab
    typescript-go
    vscode-langservers-extracted
    vtsls
    yaml-language-server
  ];
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
  };
}

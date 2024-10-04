{ config, pkgs, ... }:

{
  imports = [
    ./nixvim.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  nixpkgs.config.allowUnfree = true;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05" ; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    restic
    screen
    powerline-fonts
    curl
    wget

    unrar
    unzip
    zip
    zstd
    xz
    gzip

    jetbrains-mono

    bazelisk

    (pkgs.writeShellScriptBin "dirsize" ''
      du -shc -- "$@" | sort --human-numeric-sort --reverse
    '')
  ];

  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts.monospace = [
    "JetBrains Mono"
  ];

  programs.git = { 
    enable = true;
    userName  = "Ilia Malakhov";
    userEmail = "ilya.malakhov4@gmail.com";
    signing = {
      signByDefault = true;
      key = "64ECA0776D0E99AC";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      bazel = "bazelisk";
    };
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "vi-mode" "extract " ];
      theme = "apple";
    };
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };


  programs.ripgrep.enable = true;
  programs.fd.enable = true;
  programs.bat.enable = true;
  programs.htop.enable = true;
  programs.fzf.enable = true;

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # programs.gnome-shell.enable = true;

#  dconf = {
#    enable = true;
#    settings."org/gnome/shell" = {
#      disable-user-extensions = false;
#      enabled-extensions = with pkgs.gnomeExtensions; [
#        blur-my-shell.extensionUuid
#        gsconnect.extensionUuid
#        "dash-to-dock"
#        "gsconnect"
#      ];
#    };
#  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ilma4/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

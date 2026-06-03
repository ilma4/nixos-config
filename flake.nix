{
  description = "Configs for all my devices";

  inputs = {
    # Core Nixpkgs inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # System-specific inputs
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home and user management
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-darwin = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Security and secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix-darwin = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Development and tooling
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay-darwin = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    hoopsnake = {
      url = "github:boinkor-net/hoopsnake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yaml = {
      url = "github:milahu/nix-yaml";
      flake = false;
    };

    # Platform-specific utilities
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-darwin,
    nixpkgs-unstable,
    home-manager,
    nix-darwin,
    ...
  }: let
    # System aliases for readability
    systems = {
      x86-linux = "x86_64-linux";
      arm64-linux = "aarch64-linux";
      arm64-macos = "aarch64-darwin";
    };

    # Centralized package sets with common configuration
    mkPkgs = nixpkgsInput: system: overlays:
      import nixpkgsInput {
        inherit system;
        config.allowUnfree = true;
        inherit overlays;
      };

    # Common overlays
    commonOverlays = [
      inputs.rust-overlay.overlays.default
      (import ./overlays/monitor-input-overlay.nix)
      (import ./overlays/beads-ui-overlay.nix)
      (import ./overlays/paperless-mcp-overlay.nix)
      (import ./overlays/prometheus-smartctl-exporter-overlay.nix)
      (import ./overlays/restic-exporter-overlay.nix)
    ];

    darwinOverlays =
      commonOverlays
      ++ [
        (import ./overlays/darwin-signing-workaround-overlay.nix)
      ];

    # Centralized package sets
    pkgsSets = system: let
      isDarwin = nixpkgs.lib.hasSuffix "darwin" system;
    in {
      stable =
        if isDarwin
        then mkPkgs nixpkgs-darwin system darwinOverlays
        else mkPkgs nixpkgs system commonOverlays;
      unstable = mkPkgs nixpkgs-unstable system [];
    };

    # Base special arguments shared across all configurations
    baseSpecialArgs = {
      inherit inputs;
    };

    builders = {
      nixos = nixpkgs.lib.nixosSystem;
      darwin = nix-darwin.lib.darwinSystem;
      home = home-manager.lib.homeManagerConfiguration;
    };

    baseModule = {
      nixos = ./modules/base.nix;
      # darwin = ./darwin-modules/base.nix;
      home = ./home/base.nix;
    };

    # workaround over home-manager using `extraSpecialArgs` instead of `specialArgs`
    mkSpecialArgs = type: extraArgs:
      if type == "home"
      then {extraSpecialArgs = extraArgs;}
      else {specialArgs = extraArgs;};
  in let
    mkAny = type: {
      system,
      module,
      extraSpecialArgs ? {},
    }: let
      pkgs = (pkgsSets system).stable;
      specialArgs = mkSpecialArgs type (
        baseSpecialArgs
        // {pkgs-unstable = (pkgsSets system).unstable;}
        // {constants = import ./constants.nix;}
        // {
          myLib = {
            secrets = ./secrets;
            yaml = {
              fromYaml = (import "${inputs.yaml}/from-yaml.nix") {lib = pkgs.lib;};
              toYaml = (import "${inputs.yaml}/to-yaml.nix") {lib = pkgs.lib;};
            };
            unifiedModules = let
              checkers = {
                isDarwin = type == "darwin";
                isNixos = type == "nixos";
                isHomeManager = type == "home";
                isLinux = type == "nixos" || type == "home";
              };
            in {
              enableForConfigurations = types: configuration:
                if builtins.any (x: checkers."${x}") types
                then configuration
                else {};
              inherit checkers;
            };
          };
        }
        // extraSpecialArgs
      );
    in
      builders.${type} ({
          inherit pkgs;
          modules = [
            baseModule.${type} or {}
            module
            ({lib, ...}: {
              options.flake-source = lib.mkOption {
                type = lib.types.nullOr lib.types.singleLineStr;
                description = "The source of the flake";
                example = "/home/user/flake-directory";
                default = null;
              };
              config = {};
            })
          ];
        }
        // specialArgs);

    mkNixosSystem = mkAny "nixos";
    mkDarwinSystem = mkAny "darwin";
    mkHomeConfig = mkAny "home";
  in {
    # use `nix run .#<package-name>` to run one of those packages
    # e.g. `nix run .#monitor-input`
    packages = builtins.listToAttrs (builtins.map (system: {
      name = system;
      value = let
        pkgs = (pkgsSets system).stable;
      in {
        inherit (pkgs) monitor-input beads-ui paperless-mcp restic-exporter;
      };
    }) (builtins.attrValues systems));

    devShells = builtins.listToAttrs (builtins.map (system: {
      name = system;
      value = let
        pkgs = (pkgsSets system).stable;
      in {
        default = pkgs.mkShell {
          packages = [
            (pkgs.haskellPackages.ghcWithPackages (p:
              with p; [
                aeson
                yaml
                bytestring
                containers
                process
                extra
                filepath
                http-client
                http-conduit
              ]))
            pkgs.haskellPackages.hie-bios
            pkgs.haskell-language-server
          ];
        };
      };
    }) (builtins.attrValues systems));

    # NixOS Configurations
    nixosConfigurations = {
      rex = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/rex/rex.nix;
      };

      nas = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/nas/nas.nix;
      };

      openclaw = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/openclaw/openclaw.nix;
      };

      msi-modern = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/msi-modern/msi-modern.nix;
      };
    };

    # Darwin Configurations
    darwinConfigurations = {
      quicksilver = mkDarwinSystem {
        system = systems.arm64-macos;
        module = ./hosts/quicksilver/quicksilver.nix;
      };
    };

    # Standalone Home Manager Configurations
    homeConfigurations = {};
  };
}

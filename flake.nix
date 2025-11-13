{
  description = "Configs for all my devices";

  inputs = {
    # Core Nixpkgs inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # System-specific inputs
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home and user management
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Security and secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Development and tooling
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hoopsnake = {
      url = "github:boinkor-net/hoopsnake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yaml = {
      url = "github:folospior/yaml.arm64.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Platform-specific utilities
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    ];

    # Centralized package sets
    pkgsSets = system: {
      stable =
        if nixpkgs.lib.hasSuffix "darwin" system
        then mkPkgs nixpkgs-darwin system commonOverlays
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
      system-manager = inputs.system-manager.lib.makeSystemConfig; # for system-manager
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
        // {
          myLib = {
            secrets = ./secrets;
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
        // {
          lib = nixpkgs.lib.extend (
            final: prev: {
              yaml = inputs.yaml.lib.${system};
            }
          );
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
    # NixOS Configurations
    nixosConfigurations = {
      rex = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/rex/rex.nix;
      };

      laat = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/laat/laat.nix;
      };

      dooku = mkNixosSystem {
        system = systems.arm64-linux;
        module = ./hosts/dooku/dooku.nix;
      };

      jailbreak = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/jailbreak/jailbreak.nix;
      };
    };

    # Darwin Configurations
    darwinConfigurations = {
      quicksilver = mkDarwinSystem {
        system = systems.arm64-macos;
        module = ./hosts/quicksilver/quicksilver.nix;
      };
    };

    # Standalone Home Manager Configuration (kept for compatibility)
    homeConfigurations = {
      anakin = mkHomeConfig {
        system = systems.x86-linux;
        module = ./hosts/anakin/anakin.nix;
      };
    };

    # System Manager Configuration
    systemConfigs = {
      default = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          inputs.nix-system-graphics.systemModules.default
          {
            config = {
              nixpkgs.hostPlatform = systems.x86-linux;
              system-graphics.enable = true;
            };
          }
        ];
      };
    };
  };
}

{
  description = "Configs for all my devices";

  inputs = {
    # Core Nixpkgs inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";

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
    flake-utils,
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
      stable = mkPkgs nixpkgs system commonOverlays;
      darwin = mkPkgs nixpkgs-darwin system commonOverlays;
      unstable = mkPkgs nixpkgs-unstable system [];
    };

    # Base special arguments shared across all configurations
    baseSpecialArgs = {
      inherit inputs;
      flake-location = "${self}";
    };

    # Helper function to create NixOS system configurations
    mkNixosSystem = {
      system,
      module,
      extraSpecialArgs ? {},
    }: let
      pkgs = (pkgsSets system).stable;
      specialArgs =
        baseSpecialArgs
        // {
          pkgs-unstable = (pkgsSets system).unstable;
        }
        // extraSpecialArgs;
    in
      nixpkgs.lib.nixosSystem {
        inherit pkgs system specialArgs;
        modules = [module];
      };

    # Helper function to create Darwin system configurations
    mkDarwinSystem = {
      system,
      module,
      extraSpecialArgs ? {},
    }: let
      pkgs = (pkgsSets system).darwin;
      specialArgs =
        baseSpecialArgs
        // {
          pkgs-unstable = (pkgsSets system).unstable;
        }
        // extraSpecialArgs;
    in
      nix-darwin.lib.darwinSystem {
        inherit pkgs specialArgs;
        modules = [module];
      };

    # Helper function to create Home Manager configurations
    mkHomeConfig = {
      system,
      module,
      extraSpecialArgs ? {},
    }: let
      pkgs = (pkgsSets system).stable;
      extraSpecialArgs' =
        baseSpecialArgs
        // {
          pkgs-unstable = (pkgsSets system).unstable;
        }
        // extraSpecialArgs;
    in
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [module];
        extraSpecialArgs = extraSpecialArgs';
      };
  in
    flake-utils.lib.eachDefaultSystem (system: {
      # Per-system outputs can be added here if needed
    })
    // {
      # NixOS Configurations
      nixosConfigurations = {
        ilma4-bkp = mkNixosSystem {
          system = systems.x86-linux;
          module = ./hosts/bkp/configuration.nix;
        };

        ilma4-nas = mkNixosSystem {
          system = systems.x86-linux;
          module = ./hosts/nas/configuration.nix;
        };

        ilma4-arm-vm = mkNixosSystem {
          system = systems.arm64-linux;
          module = ./hosts/arm-vm/configuration.nix;
        };

        i4-ideapad-wsl = mkNixosSystem {
          system = systems.x86-linux;
          module = ./hosts/i4-ideapad-wsl/configuration.nix;
        };
      };

      # Darwin Configurations
      darwinConfigurations = {
        quicksilver = mkDarwinSystem {
          system = systems.arm64-macos;
          module = ./hosts/quicksilver/configuration.nix;
        };
      };

      # Standalone Home Manager Configuration (kept for compatibility)
      homeConfigurations = {
        "ilma4" = mkHomeConfig {
          system = systems.x86-linux;
          module = ./hosts/main/home.nix;
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

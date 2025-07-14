{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    hoopsnake = {
      url = "github:boinkor-net/hoopsnake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-system-graphics = {
      url = "github:soupglasses/nix-system-graphics";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    #flake-root.url = "github:srid/flake-root";

    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-darwin,
    home-manager,
    nix-darwin,
    mcp-nixos,
    ...
  }: let
    x86-linux = "x86_64-linux";
    arm64-linux = "aarch64-linux";
    arm64-macos = "aarch64-darwin";
  in {
    nixosConfigurations.ilma4-bkp = nixpkgs.lib.nixosSystem {
      pkgs = import nixpkgs {
        system = x86-linux;
        config.allowUnfree = true;
        overlays = [
          inputs.rust-overlay.overlays.default
        ];
      };
      system = x86-linux;
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/bkp/configuration.nix
      ];
    };

    nixosConfigurations.ilma4-nas = nixpkgs.lib.nixosSystem {
      pkgs = import nixpkgs {
        system = x86-linux;
        config.allowUnfree = true;
      };
      system = x86-linux;
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/nas/configuration.nix
      ];
    };

    nixosConfigurations.ilma4-arm-vm = nixpkgs.lib.nixosSystem {
      pkgs = import nixpkgs {
        system = arm64-linux;
        config.allowUnfree = true;
      };
      system = arm64-linux;
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
      };

      modules = [
        ./hosts/arm-vm/configuration.nix
      ];
    };

    nixosConfigurations.i4-ideapad-wsl = nixpkgs.lib.nixosSystem {
      pkgs = import nixpkgs {
        system = x86-linux;
        config.allowUnfree = true;
      };
      system = x86-linux;
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
      };

      modules = [
        ./hosts/i4-ideapad-wsl/configuration.nix
      ];
    };

    nixosConfigurations.i4-torrent-vm = nixpkgs.lib.nixosSystem {
      pkgs = import nixpkgs {
        system = arm64-linux;
        config.allowUnfree = true;
      };
      system = arm64-linux;
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
      };

      modules = [
        ./hosts/i4-torrent-vm/configuration.nix
      ];
    };

    homeConfigurations."ilma4" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = x86-linux;
        overlays = [
          inputs.rust-overlay.overlays.default
        ];
      };

      extraSpecialArgs = {
        inherit inputs;
        flake-location = "${self}";
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/main/home.nix
      ];
    };

    darwinConfigurations."DE-UNIT-1832" = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit inputs;
        flake-location = "${self}";
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = arm64-macos;
          config.allowUnfree = true;
        };
      };

      pkgs = import nixpkgs-darwin {
        system = arm64-macos;
        config.allowUnfree = true;
        overlays = [
          inputs.rust-overlay.overlays.default
        ];
      };

      modules = [
        ./hosts/jb-macbook/configuration.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.extraSpecialArgs = {
            inherit inputs;
            flake-location = "${self}";
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = arm64-macos;
              config.allowUnfree = true;
            };
          };
        }
      ];
    };

    systemConfigs.default = inputs.system-manager.lib.makeSystemConfig {
      modules = [
        inputs.nix-system-graphics.systemModules.default
        {
          config = {
            nixpkgs.hostPlatform = "x86_64-linux";
            # system-manager.allowAnyDistro = true;
            system-graphics.enable = true;
          };
        }
      ];
    };

    homeConfigurations."malakhov" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {system = x86-linux;};
      extraSpecialArgs = {
        inherit inputs;
        flake-location = "${self}";
      };

      modules = [
        ./hosts/apal-server/home.nix
      ];
    };
  };
}

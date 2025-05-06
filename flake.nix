{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    deploy-rs.url = "github:serokell/deploy-rs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    hoopsnake = {
      url = "github:boinkor-net/hoopsnake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    #flake-root.url = "github:srid/flake-root";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-darwin,
    home-manager,
    nixgl,
    nix-darwin,
    deploy-rs,
    ...
  }: let
    x86-linux = "x86_64-linux";
    arm64-linux = "aarch64-linux";
    arm64-macos = "aarch64-darwin";
    nixos-modules = "${self}/modules";
    home-manager-modules = "${self}/home";
    dotfiles = "${self}/dotfiles";
    secrets = "${self}/secrets";
    darwin-modules = "${self}/darwin-modules";
  in {
    deploy.nodes = {
      ilma4-bkp = {
        hostname = "ilma4-bkp";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib."x86_64-linux".activate.nixos self.nixosConfigurations.ilma4-bkp;
        };
      };
      ilma4-nas = {
        hostname = "ilma4-nas";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib."x86_64-linux".activate.nixos self.nixosConfigurations.ilma4-nas;
        };
      };
      ilma4-arm-vm = {
        hostname = "192.168.64.12";
        profiles.system = {
          user = "root";
          ssh_user = "root";
          path = deploy-rs.lib."aarch64-linux".activate.nixos self.nixosConfigurations.ilma4-arm-vm;
        };
      };
    };
    # deploy-rs checks
    # checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

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
        inherit dotfiles;
        inherit secrets;
        modules = nixos-modules;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/bkp/configuration.nix
        inputs.hoopsnake.nixosModules.default # ssh via tailscale in initrd
        home-manager.nixosModules.home-manager
        inputs.sops-nix.nixosModules.sops
        {
          home-manager.useGlobalPkgs = true;
          home-manager.extraSpecialArgs = {
            inherit inputs;
            inherit dotfiles;
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = x86-linux;
              config.allowUnfree = true;
            };
            modules = home-manager-modules;
          };
        }
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
        inherit dotfiles;
        inherit secrets;
        modules = nixos-modules;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/nas/configuration.nix
        home-manager.nixosModules.home-manager
        inputs.sops-nix.nixosModules.sops
        {
          home-manager.useGlobalPkgs = true;
          home-manager.extraSpecialArgs = {
            inherit inputs;
            inherit dotfiles;
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = x86-linux;
              config.allowUnfree = true;
            };
            modules = home-manager-modules;
          };
        }
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
        inherit dotfiles;
        inherit secrets;
        modules = nixos-modules;
      };

      modules = [
        ./hosts/arm-vm/configuration.nix
        inputs.sops-nix.nixosModules.sops
      ];
    };

    homeConfigurations."ilma4" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = x86-linux;
        overlays = [
          nixgl.overlay
          inputs.rust-overlay.overlays.default
        ];
      };

      extraSpecialArgs = {
        inherit inputs;
        inherit dotfiles;
        modules = home-manager-modules;
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
        modules = darwin-modules;
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
            inherit dotfiles;
            modules = home-manager-modules;
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = arm64-macos;
              config.allowUnfree = true;
            };
          };
        }
      ];
    };

    homeConfigurations."malakhov" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {system = x86-linux;};
      extraSpecialArgs = {
        inherit inputs;
        inherit dotfiles;
        modules = home-manager-modules;
      };

      modules = [
        ./hosts/apal-server/home.nix
      ];
    };
  };
}

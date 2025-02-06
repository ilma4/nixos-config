{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-24.11";
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

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
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
    nix-on-droid,
    ...
  }: let
    x86-linux = "x86_64-linux";
    arm64-macos = "aarch64-darwin";
    nixos-modules = "${self}/modules";
    home-manager-modules = "${self}/home";
    dotfiles = "${self}/dotfiles";
    darwin-modules = "${self}/darwin-modules";
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
        inherit dotfiles;
        modules = nixos-modules;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = x86-linux;
          config.allowUnfree = true;
        };
      };

      modules = [
        ./hosts/bkp/configuration.nix
        home-manager.nixosModules.home-manager
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

    darwinConfigurations."DE-UNIT-1880" = nix-darwin.lib.darwinSystem {
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
    nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import nixpkgs {
        system = "aarch64-linux";

        overlays = [
          nix-on-droid.overlays.default
          # add other overlays
        ];
      };

      extraSpecialArgs = { inherit inputs; };

      # set path to home-manager flake
      home-manager-path = home-manager.outPath;
      modules = [
        ./hosts/oneplus10R/nix-on-droid.nix
        ({...}: {
          home-manager.extraSpecialArgs = {modules = home-manager-modules; dotfiles = dotfiles; inherit inputs;};
        })
      ];
    };
  };
}

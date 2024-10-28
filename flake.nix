{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-24.05";
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
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-root = {
      url = "github:srid/flake-root";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    nixgl,
    nix-darwin,
    ...
  }: let
    x86-linux = "x86_64-linux";
    arm64-macos = "aarch64-darwin";
    nixos-modules = "${self}/modules";
    home-manager-modules = "${self}/home";
    dotfiles = "${self}/dotfiles";
  in {
    nixosConfigurations.ilma4-bkp = nixpkgs.lib.nixosSystem {
      system = x86-linux;
      specialArgs = {
        inherit inputs;
        modules = nixos-modules;
      };

      modules = [
        ./hosts/bkp/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.extraSpecialArgs = {
            inherit inputs;
            inherit dotfiles;
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

    darwinConfigurations."DE-UNIT-1832" = nix-darwin.lib.darwinSystem {
      pkgs = import nixpkgs {
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
          };

          home-manager.users.ilma4 = import ./hosts/jb-macbook/home.nix;
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

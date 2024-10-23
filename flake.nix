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

    flake-root.url = "github:srid/flake-root";
    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixvim, nixgl, nix-darwin, ... }: 
    let 
      system = "x86_64-linux";
      nixos-modules = "${self}/modules";
      home-manager-modules = "${self}/home";
      dotfiles = "${self}/dotfiles";
    in {
      nixosConfigurations.ilma4-bkp = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; modules = nixos-modules; };
        modules = [
          ./hosts/bkp/configuration.nix
          home-manager.nixosModules.home-manager {
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
          inherit system;
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
            inherit system;
            config.allowUnfree = true;
          };
        };

        modules = [ 
          ./hosts/main/home.nix 
          nixvim.homeManagerModules.nixvim
        ];
      };

      darwinConfigurations."DE-UNIT-1832" = nix-darwin.lib.darwinSystem {
        modules = [
          ./hosts/jb-macbook/configuration.nix
          inputs.mac-app-util.darwinModules.default

          home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          #home-manager.useUserPackages = true;

          home-manager.extraSpecialArgs = {
            inherit inputs;
            inherit dotfiles;
            modules = home-manager-modules;
            outOfStoreSymlink = (cfg: x: cfg.lib.file.mkOutOfStoreSymlink "/Users/ilma4/.config/nixos-config/dotfiles/${x}");
          };

          home-manager.sharedModules = [
            inputs.mac-app-util.homeManagerModules.default
          ];

          home-manager.users.ilma4 = import ./hosts/jb-macbook/home.nix;
          }
        ];
      };

      homeConfigurations."malakhov" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };

        extraSpecialArgs = {
          inherit inputs;
          inherit dotfiles;
          modules = home-manager-modules;
        };

        modules = [ 
          ./hosts/apal-server/home.nix 
          nixvim.homeManagerModules.nixvim
        ];
      };
    };
}

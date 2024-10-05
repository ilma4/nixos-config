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
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixvim, nixgl, ... }: 
    let 
      system = "x86_64-linux";
    in {
      nixos-modules = "${self}/modules";
      home-manager-modules = "${self}/home";
      dotfiles = "${self}/dotfiles";

      nixosConfigurations.ilma4-bkp = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; modules = self.nixos-modules; };
        modules = [
          ./hosts/bkp/configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.extraSpecialArgs = { inherit inputs; modules = self.home-manager-modules; dotfiles = self.dotfiles; };
          }
        ];
      };
      homeConfigurations."ilma4" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ nixgl.overlay ];
        };

        extraSpecialArgs = { 
          inherit inputs;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          modules = self.home-manager-modules;
          dotfiles = self.dotfiles;
        };

        modules = [ 
          ./hosts/main/home.nix 
          nixvim.homeManagerModules.nixvim
        ];
      };
      homeConfigurations."malakhov" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        modules = [ 
          ./hosts/apal-server/home.nix 
          nixvim.homeManagerModules.nixvim
        ];
      };
    };
}

{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-24.05";
       # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
       # url = "github:nix-community/nixvim/nixos-24.05";

      inputs.nixpkgs.follows = "nixpkgs";
     };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixvim, ... }: 
    let 
      system = "x86_64-linux";
    in {
    nixosConfigurations.ilma4-bkp = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # specialArgs = { inherit inputs; };
      modules = [
        ./hosts/bkp/configuration.nix
	nixvim.nixosModules.nixvim
	# nixvim.homeManagerModules.nixvim
	home-manager.nixosModules.default
      ];
    };
    nixosConfigurations.ilma4-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # specialArgs = { inherit inputs; };
      modules = [
        ./vm-conf.nix
	nixvim.nixosModules.nixvim
	# nixvim.homeManagerModules.nixvim
	home-manager.nixosModules.default
      ];
    };
      homeConfigurations."ilma4" = home-manager.lib.homeManagerConfiguration {
	pkgs = nixpkgs.legacyPackages.${system};

        modules = [ 
	  ./hosts/main/home.nix 
          nixvim.homeManagerModules.nixvim
	];
      };
      homeConfigurations."malakhov" = home-manager.lib.homeManagerConfiguration {
	pkgs = nixpkgs.legacyPackages.${system};

        modules = [ 
	  ./hosts/main/home.nix 
          nixvim.homeManagerModules.nixvim
	];
      };
  };
}

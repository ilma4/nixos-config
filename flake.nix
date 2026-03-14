{
  description = "Configs for all my devices";

  inputs = {
    # Core Nixpkgs inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # System-specific inputs
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs.url = "github:serokell/deploy-rs";

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home and user management
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
    quickemu = {
      url = "github:quickemu-project/quickemu/4.9.9";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    monitor-input-rs = {
      url = "github:kojiishi/monitor-input-rs";
      flake = false;
    };

    # Platform-specific utilities
    nix-rosetta-builder = {
      url = "git+https://nossa.ee/~talya/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs";
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

    monitorInputOverlay = final: prev: {
      monitor-input = final.rustPlatform.buildRustPackage {
        pname = "monitor-input";
        version = "unstable";

        src = inputs.monitor-input-rs;

        cargoLock = {
          lockFile = "${inputs.monitor-input-rs}/Cargo.lock";
        };

        # runtime dependencies
        buildInputs = final.lib.optionals final.stdenv.isLinux [
          final.systemd
        ];

        meta = with final.lib; {
          description = "Control monitor input sources";
          homepage = "https://github.com/kojiishi/monitor-input-rs";
          license = licenses.mit;
          mainProgram = "monitor-input";
          platforms = platforms.all;
        };
      };
    };

    # Common overlays
    commonOverlays = [
      inputs.rust-overlay.overlays.default
      monitorInputOverlay
      (import ./overlays/beads-ui-overlay.nix)
      (import ./overlays/paperless-mcp-overlay.nix)
      (import ./overlays/pi-coding-agent-overlay.nix)
    ];

    darwinOverlays = commonOverlays ++ [inputs.quickemu.overlays.default];

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
        // {constants = import ./constants.nix;}
        // {
          myLib = {
            secrets = ./secrets;
            yaml = inputs.yaml.lib.${system};
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
        inherit (pkgs) monitor-input beads-ui paperless-mcp pi-coding-agent;
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

      dooku = mkNixosSystem {
        system = systems.arm64-linux;
        module = ./hosts/dooku/dooku.nix;
      };

      jailbreak = mkNixosSystem {
        system = systems.x86-linux;
        module = ./hosts/jailbreak/jailbreak.nix;
      };

      nixos-test = mkNixosSystem {
        system = systems.arm64-linux;
        module = ./hosts/nixos-test/nixos-test.nix;
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
      msi-modern = mkHomeConfig {
        system = systems.x86-linux;
        module = ./hosts/msi-modern/msi-modern.nix;
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

    deploy.nodes.nas = {
      hostname = "nas.local";
      profiles.system = {
        sshUser = "root";
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nas;
      };
    };

    # This is highly advised, and will prevent many possible mistakes
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
  };
}

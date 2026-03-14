{
  pkgs,
  inputs,
  pkgs-unstable,
  ...
}: let
  containerName = "agent-dev-box";

  # Dedicated key that is forced into agent-dev-box only.
  # TODO: dedicated key
  containerOnlySshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4gqAl3ZqveXhNkOrOb6tv9EBbSfV3RlvvP778PzAyN ilma4@DE-UNIT-1832";

  mkJunieCli = pkgs:
    pkgs.writeShellScriptBin "junie" ''
      set -euo pipefail
      exec ${pkgs.nodejs}/bin/npx --yes @jetbrains/junie-cli "$@"
    '';

  enterScript = pkgs.writeShellScriptBin "agent-dev-box-enter" ''
    set -euo pipefail

    if [ "$(id -u)" -eq 0 ]; then
      ${pkgs.nixos-container}/bin/nixos-container start ${containerName}
      exec ${pkgs.systemd}/bin/machinectl shell ilma4@${containerName}
    fi

    ${pkgs.sudo}/bin/sudo ${pkgs.nixos-container}/bin/nixos-container start ${containerName}
    exec ${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/machinectl shell ilma4@${containerName}
  '';
in {
  containers.${containerName} = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.241.0.1";
    localAddress = "10.241.0.2";

    config = {pkgs, ...}: {
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];

      networking.hostName = containerName;
      nixpkgs.config.allowUnfree = true;
      services.openssh.enable = true;
      programs.zsh.enable = true;

      users.users.ilma4 = {
        isNormalUser = true;
        shell = pkgs.zsh;
        extraGroups = ["wheel"];
      };

      security.sudo.extraRules = [
        {
          users = ["ilma4"];
          commands = [
            {
              command = "ALL";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit inputs;
        inherit pkgs-unstable;
      };

      home-manager.users.ilma4 = {
        imports = [
          ./home.nix
        ];

        i4.dev.enable = true;
        configure-ssh = false;

        home.packages = with pkgs; [
          codex
          claude-code
          gemini-cli
          opencode
          (mkJunieCli pkgs)
        ];
      };

      system.stateVersion = "24.05";
    };
  };

  environment.systemPackages = [
    enterScript
  ];

  users.users.agent-dev-box-ssh = {
    isNormalUser = true;
    description = "Restricted SSH account to enter agent-dev-box container";
    createHome = false;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # TODO: enable with new key
      # "command=\"${pkgs.sudo}/bin/sudo /run/current-system/sw/bin/agent-dev-box-enter\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding ${containerOnlySshPublicKey}"
    ];
  };

  security.sudo.extraRules = [
    {
      users = ["agent-dev-box-ssh"];
      commands = [
        {
          command = "/run/current-system/sw/bin/agent-dev-box-enter";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}

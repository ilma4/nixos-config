{
  config,
  pkgs,
  ...
}: let
  agentSocket = "$XDG_RUNTIME_DIR/ssh-tpm-agent.sock";
in {
  home.packages = [pkgs.ssh-tpm-agent];

  home.sessionVariables.SSH_AUTH_SOCK = agentSocket;
  # Refresh even when Home Manager's session variables were already sourced
  # by a parent process (for example, an existing tmux server).
  programs.zsh.envExtra = ''
    if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
      export SSH_AUTH_SOCK="${agentSocket}"
    fi
  '';
  programs.ssh.settings = {
    "*" = {
      IdentityAgent = "\${XDG_RUNTIME_DIR}/ssh-tpm-agent.sock";
      IdentitiesOnly = true;
    };
    # IdentityFile is additive, so the general TPM key must not match GitHub.
    "* !github.com".IdentityFile = "~/.ssh/id_ecdsa_msi_tpm.pub";
    "github.com".IdentityFile = "~/.ssh/id_ecdsa_msi_github_tpm.pub";
  };

  systemd.user.sockets.ssh-tpm-agent = {
    Unit.Description = "TPM-backed SSH agent socket";
    Socket = {
      ListenStream = "%t/ssh-tpm-agent.sock";
      SocketMode = "0600";
    };
    Install.WantedBy = ["sockets.target"];
  };

  systemd.user.services.ssh-tpm-agent = {
    Unit = {
      Description = "TPM-backed SSH agent";
      Requires = ["ssh-tpm-agent.socket"];
    };
    Service = {
      ExecStart = "${pkgs.ssh-tpm-agent}/bin/ssh-tpm-agent --key-dir ${config.home.homeDirectory}/.ssh";
      Environment = ["SSH_TPM_AUTH_SOCK=%t/ssh-tpm-agent.sock"];
    };
  };
}

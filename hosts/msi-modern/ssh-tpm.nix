{
  config,
  pkgs,
  ...
}: {
  home.packages = [pkgs.ssh-tpm-agent];

  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-tpm-agent.sock";
  programs.ssh.settings."*" = {
    IdentityAgent = "\${XDG_RUNTIME_DIR}/ssh-tpm-agent.sock";
    IdentityFile = "~/.ssh/id_ecdsa_msi_tpm.pub";
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

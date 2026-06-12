{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.top-commands;
in {
  options.top-commands = {
    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      example = {
        hello-world = "echo 'Hello World!'";
        "a" = "echo 'A'";
      };
      description = "Named favourite commands";
    };
    tofi-command = lib.mkOption {
      type = lib.types.str;
      example = "\${tofi} --width 800 --height 700 --font /usr/share/fonts/TTF/JetBrainsMono-Light.ttf";
      description = "Command to run tofi";
    };
  };

  config = let
    rustRawString = value: let
      hashes = "########";
    in ''r${hashes}"${value}"${hashes}'';
    commandsAsMap =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList (key: value: "(${rustRawString key}, ${rustRawString value}),") cfg.commands);
    commandNameArgs = lib.concatStringsSep " " (map lib.escapeShellArg (lib.attrNames cfg.commands));
  in let
    launch-favorite =
      pkgs.writers.writeRustBin "launch-favorite" {rustcArgs = ["-C" "opt-level=3"];}
      /*
      rust
      */
      ''
        use std::env;
        use std::os::unix::process::CommandExt;
        use std::process::{Command, Stdio};
        use std::collections::HashMap;

        fn main() {
            let command_name = env::args().nth(1).unwrap_or_else(|| {
                eprintln!("Usage: launch-favorite <command-name>");
                std::process::exit(64);
            });
            let name_to_command = HashMap::from([
                ${commandsAsMap}
            ]);
            let command = match name_to_command.get(command_name.as_str()) {
                Some(command) => *command,
                None => {
                    eprintln!("Unknown favorite command: {command_name}");
                    std::process::exit(64);
                }
            };
            let err = Command::new("${pkgs.runtimeShell}")
                .arg("-c")
                .arg(command)
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .stdin(Stdio::inherit())
                .exec();
            eprintln!("Command {command_name} failed with error {err}");
            std::process::exit(1);
        }
      '';

    select-favorite = pkgs.writeShellScriptBin "select-favorite" ''
      set -euo pipefail
      printf '%s\n' ${commandNameArgs} | ${cfg.tofi-command}
    '';
    exec-favorite = pkgs.writeShellScriptBin "exec-favorite" ''
      set -euo pipefail
      selected="$(${select-favorite}/bin/select-favorite)" || exit 0
      [ -n "$selected" ] || exit 0
      exec ${launch-favorite}/bin/launch-favorite "$selected"
    '';

    sway-modifier = config.wayland.windowManager.sway.config.modifier;
  in {
    home.packages = [launch-favorite exec-favorite select-favorite];
    wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
      "${sway-modifier}+y" = "exec ${exec-favorite}/bin/exec-favorite";
    };
  };
}

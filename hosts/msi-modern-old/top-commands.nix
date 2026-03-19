inputs @ {
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
    commandsAsMap =
      lib.attrsets.foldlAttrs
      (acc: key: value: "${acc}\n(\"${key}\", \"${value}\"),")
      ""
      cfg.commands;
    commandNames =
      lib.attrsets.foldlAttrs
      (acc: key: _: "${acc}\n${key}") ""
      cfg.commands;
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
            let command_name = env::args().nth(1).unwrap();
            let name_to_command = HashMap::from([
                ${commandsAsMap}
            ]);
            let mut command = name_to_command[command_name.as_str()].split_whitespace();
            let err = Command::new(command.next().unwrap())
                .args(command)
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .stdin(Stdio::inherit())
                .exec();
            eprintln!("Command {command_name} failed with error {err}");
        }
      '';

    select-favorite = pkgs.writeShellScriptBin "select-favorite" ''
      printf "${commandNames}" | ${cfg.tofi-command}
    '';
    exec-favorite = pkgs.writeShellScriptBin "exec-favorite" ''
      ${select-favorite}/bin/select-favorite | xargs -I{} ${launch-favorite}/bin/launch-favorite {}
    '';

    sway-modifier = config.wayland.windowManager.sway.config.modifier;
  in {
    home.packages = [launch-favorite exec-favorite select-favorite];
    wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
      "${sway-modifier}+y" = "exec ${exec-favorite}/bin/exec-favorite";
    };
  };
}

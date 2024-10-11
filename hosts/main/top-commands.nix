inputs@{ config, lib, pkgs, ... }:
let cfg = config.top-commands; in
{
  options.top-commands = {
    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { test = "echo test"; };
      example = { hello-world = "echo 'Hello World!'"; };
      description = "Named favourite commands";
    };
    tofi-command = lib.mkOption {
      type = lib.types.str;
      default = "tofi";
      example = "\${tofi} --width 800 --height 700 --font /usr/share/fonts/TTF/JetBrainsMono-Light.ttf";
      description = "Command to run tofi";
    };
  };
  

  config = let 
    # commandsAsStr = with builtins; concatStringsSep "\n" (attrValues (mapAttrs (key: value: "${key} ${value}") cfg.commands ));
    commandsAsStr = lib.attrsets.foldlAttrs 
      (acc: key: value: "${acc}\n${key} ${value}")
      ""
      cfg.commands
     ; 
    commandNames = lib.attrsets.foldlAttrs
      (acc: key: _: "${acc}\n${key}") "" cfg.commands
    ;
  in let 
    launch-favorite = (pkgs.writers.writeRustBin "launch-favorite" {} /*rust*/''
      use std::env;
      use std::os::unix::process::CommandExt;
      use std::process::{Command, Stdio};

      const FAVORITE_COMMANDS: &str = r#"
${commandsAsStr}
      "#;


      fn get_command(command_name: &str) -> &'static str {
          FAVORITE_COMMANDS
              .lines()
              .filter(|line| !line.trim().is_empty())
              .find_map(|line| {
                  let mut parts = line.splitn(2, ' ');
                  let name = parts.next().unwrap();
                  if name != command_name {
                      None
                  } else {
                      let command = parts.next().unwrap();
                      Some(command)
                  }
              })
              .unwrap()
      }


      fn main() {
          let command_name = env::args().nth(1).unwrap();
          let mut command = get_command(command_name.as_str()).split_whitespace();
          let err = Command::new(command.next().unwrap())
              .args(command)
              .stdout(Stdio::inherit())
              .stderr(Stdio::inherit())
              .stdin(Stdio::inherit())
              .exec();
          eprintln!("Command {command_name} failed with error {err}");
      }
    '');

    select-favorite = (pkgs.writeShellScriptBin "select-favorite" ''
      printf "${commandNames}" | ${cfg.tofi-command}
    '');
    exec-favorite = (pkgs.writeShellScriptBin "exec-favorite" ''
      ${select-favorite}/bin/select-favorite | xargs -I{} ${launch-favorite}/bin/launch-favorite {}
    '');
    in {
    home.packages = [launch-favorite exec-favorite select-favorite];

    wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
      "${config.wayland.windowManager.sway.config.modifier}+y" = "exec ${exec-favorite}/bin/exec-favorite";
    };
  };
}
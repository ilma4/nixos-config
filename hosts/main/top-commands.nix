inputs@{ config, lib, pkgs, ... }:
let cfg = config.top-commands; in
{
  options.top-commands.commands = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { test = "echo test"; };
    example = { hello-world = "echo 'Hello World!'"; };
    description = "Named favourite commands";
  };
  

  config = let 
    # myStr = with builtins; concatStringsSep "\n" (attrValues (mapAttrs (key: value: "${key} ${value}") cfg.commands ));
    myStr = lib.attrsets.foldlAttrs 
      (acc: key: value: "${key} ${value}\n")
      ""
      cfg.commands
     ; 
  in {
    home.packages = [
      (pkgs.writers.writeRustBin "launch-favorite" {} /*rust*/''
      use std::env;
      use std::os::unix::process::CommandExt;
      use std::process::{Command, Stdio};

      const FAVORITE_COMMANDS: &str = r#"
${myStr}
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
    '')] ;
  };
}

/*
Adds command `i4-journalctl-no-compose` to see journald logs without docker-compose services and containers.
on 2025-02-21 journalctl doesn't support "exclude" feature, so this script filters strings manually.
*/
{
  lib,
  myLib,
  pkgs,
  config,
  ...
}: let
  enabledComposeServices = lib.filterAttrs (_: svc: svc.enable) config.dockerCompose;
  composeServiceUnits = map (name: "${name}.service") (lib.attrNames enabledComposeServices);
  composeContainerNames = lib.pipe enabledComposeServices [
    (lib.mapAttrsToList (name: svc: let
      composeForParse = builtins.toFile "docker-compose-journalctl-${name}.yml" (
        # safe, because later we only use container_name and serviceName
        builtins.unsafeDiscardStringContext (builtins.readFile svc.composeFile)
      );
      services = (myLib.yaml.fromYaml composeForParse).services or {};
    in (lib.mapAttrsToList (serviceName: service: service.container_name or serviceName) services)))
    lib.flatten
    lib.unique
  ];
  journalctlWithoutCompose =
    pkgs.writers.writeRustBin "i4-journalctl-no-compose" {rustcArgs = ["-C" "opt-level=3"];}
    ''
      use std::env;
      use std::io::{self, BufRead, BufReader, Write};
      use std::process::{Command, Stdio};

      unsafe extern "C" {
          fn isatty(fd: i32) -> i32;
      }

      fn usage() {
          println!("Usage: i4-journalctl-no-compose [journalctl args]");
          println!();
          println!("Show journald logs while excluding docker-compose services and containers from this host.");
          println!();
          println!("Examples:");
          println!("  i4-journalctl-no-compose");
          println!("  i4-journalctl-no-compose --since \"1 hour ago\"");
          println!("  i4-journalctl-no-compose -b -p warning");
      }

      fn has_arg(args: &[String], value: &str) -> bool {
          args.iter().any(|arg| arg == value)
      }

      fn has_follow_arg(args: &[String]) -> bool {
          has_arg(args, "-f") || has_arg(args, "--follow")
      }

      fn use_pager(args: &[String]) -> bool {
          if has_arg(args, "--no-pager") || has_follow_arg(args) {
              return false;
          }
          unsafe { isatty(1) == 1 }
      }

      fn contains_any(haystack: &[u8], needles: &[Vec<u8>]) -> bool {
          needles.iter().any(|needle| {
              !needle.is_empty()
                  && haystack
                      .windows(needle.len())
                      .any(|window| window == needle.as_slice())
          })
      }

      fn main() {
          let args: Vec<String> = env::args().skip(1).collect();

          if matches!(args.first().map(String::as_str), Some("-h" | "--help")) {
              usage();
              return;
          }

          let excluded_units: &[&str] = &${builtins.toJSON composeServiceUnits};
          let excluded_containers: &[&str] = &${builtins.toJSON composeContainerNames};
          let mut excluded_patterns: Vec<Vec<u8>> = excluded_units
              .iter()
              .chain(excluded_containers.iter())
              .map(|value| value.as_bytes().to_vec())
              .collect();
          excluded_patterns.sort();
          excluded_patterns.dedup();
          let should_use_pager = use_pager(&args);

          let mut journalctl = Command::new("${pkgs.systemd}/bin/journalctl");
          journalctl.env("SYSTEMD_COLORS", "1");
          journalctl.arg("--no-pager");
          journalctl.args(&args);
          journalctl.stdin(Stdio::inherit());
          journalctl.stderr(Stdio::inherit());
          journalctl.stdout(Stdio::piped());

          let mut journalctl_child = match journalctl.spawn() {
              Ok(child) => child,
              Err(err) => {
                  eprintln!("Failed to start journalctl: {err}");
                  std::process::exit(1);
              }
          };

          let journalctl_stdout = match journalctl_child.stdout.take() {
              Some(stdout) => stdout,
              None => {
                  eprintln!("Failed to capture journalctl stdout");
                  std::process::exit(1);
              }
          };

          let mut pager_child = if should_use_pager {
              let mut pager = Command::new("${pkgs.less}/bin/less");
              pager.arg("-R");
              pager.stdin(Stdio::piped());
              pager.stdout(Stdio::inherit());
              pager.stderr(Stdio::inherit());
              match pager.spawn() {
                  Ok(child) => Some(child),
                  Err(err) => {
                      eprintln!("Failed to start pager: {err}");
                      std::process::exit(1);
                  }
              }
          } else {
              None
          };

          let mut output: Box<dyn Write> = if let Some(pager) = pager_child.as_mut() {
              match pager.stdin.take() {
                  Some(stdin) => Box::new(stdin),
                  None => {
                      eprintln!("Failed to capture pager stdin");
                      std::process::exit(1);
                  }
              }
          } else {
              Box::new(io::stdout())
          };

          let mut reader = BufReader::new(journalctl_stdout);
          let mut line = Vec::with_capacity(4096);
          loop {
              line.clear();
              let bytes_read = match reader.read_until(b'\n', &mut line) {
                  Ok(read) => read,
                  Err(err) => {
                      eprintln!("Failed reading journalctl output: {err}");
                      std::process::exit(1);
                  }
              };

              if bytes_read == 0 {
                  break;
              }

              if contains_any(&line, &excluded_patterns) {
                  continue;
              }

              if let Err(err) = output.write_all(&line) {
                  if err.kind() == io::ErrorKind::BrokenPipe {
                      break;
                  }
                  eprintln!("Failed writing filtered output: {err}");
                  std::process::exit(1);
              }
          }

          let _ = output.flush();
          drop(output);

          let journalctl_status = match journalctl_child.wait() {
              Ok(status) => status,
              Err(err) => {
                  eprintln!("Failed waiting for journalctl: {err}");
                  std::process::exit(1);
              }
          };

          if let Some(mut pager) = pager_child {
              let pager_status = match pager.wait() {
                  Ok(status) => status,
                  Err(err) => {
                      eprintln!("Failed waiting for pager: {err}");
                      std::process::exit(1);
                  }
              };
              if !pager_status.success() {
                  std::process::exit(pager_status.code().unwrap_or(1));
              }
          }

          if !journalctl_status.success() {
              std::process::exit(journalctl_status.code().unwrap_or(1));
          }
      }
    '';
in {
  config = lib.mkIf config.i4.dockerComposeEnable {
    environment.systemPackages = [
      journalctlWithoutCompose
    ];
  };
}

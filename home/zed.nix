{
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
in {
  programs.zed-editor = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.bash; # hack to avoid installing, on darwin zed is installed via homebrew

    userSettings = {
      # AI Agent configuration
      "agent" = {
        "version" = "2";
        "default_model" = {
          "provider" = "zed.dev";
          "model" = "claude-sonnet-4";
        };
      };
      # disable ligatures
      "buffer_font_features" = {
        "calt" = false;
      };
      "vim_mode" = true;
      "autosave" = "on_focus_change";
      "auto_update" = false; # I manage update using homebrew
      "ui_font_size" = 14;
      "buffer_font_size" = 13;
      "base_keymap" = "JetBrains";
      "theme" = {
        "mode" = "system";
        "light" = "One Light";
        "dark" = "One Dark";
      };
      # "ui_font_family": "Inter",
      "buffer_font_family" = "JetBrains Mono";
      "lsp" = {
        "nixd" = {
          "settings" = {
            "diagnostic" = {
              "suppress" = ["sema-extra-with"];
            };
          };
        };
        "nil" = {
          "settings" = {
            "diagnostics" = {
              "ignored" = ["unused_binding"];
            };
            "nix" = {
              "flake" = {
                "autoArchive" = true;
              };
            };
          };
        };
      };
      "languages" = {
        "Nix" = {
          "formatter" = {
            "external" = {
              "command" = "alejandra";
              "arguments" = ["--quiet" "--"];
            };
          };
        };
      };
    };
    userKeymaps = [
      {
        "context" = "Workspace";
        "bindings" = {
          # "shift shift": "file_finder::Toggle"
          "cmd-9" = "git_panel::ToggleFocus";
          "cmd-1" = "project_panel::ToggleFocus";
          "shift-F12" = "workspace::CloseAllDocks";
        };
      }
      {
        "context" = "ProjectPanel";
        "bindings" = {
          "cmd-1" = "workspace::ToggleLeftDock";
          "shift-escape" = "workspace::ToggleLeftDock";
        };
      }
      {
        "context" = "GitPanel";
        "bindings" = {
          "escape" = "git_panel::ToggleFocus";
          "cmd-9" = "git_panel::Close";
        };
      }
      {
        "context" = "Editor";
        "bindings" = {
          # "j k": ["workspace::SendKeystrokes", "escape"]
          "alt-F12" = "terminal_panel::ToggleFocus";
          "F2" = "editor::GoToDiagnostic";
        };
      }
      {
        "context" = "Terminal";
        "bindings" = {
          "escape" = "terminal_panel::ToggleFocus";
          "cmd-t" = "workspace::NewTerminal";
          "cmd-shift-]" = "workspace::ActivateNextWindow";
          "cmd-shift-[" = "workspace::ActivatePreviousWindow";

          "alt-F12" = "workspace::ToggleBottomDock"; # toggle show/hide terminal
          "shift-escape" = "workspace::ToggleBottomDock";
        };
      }
    ];
    extensions = [
      "nix"
      "html"
      "toml"
      "dockerfile"
      "latex"
      "markdown-oxide"
      "xml"
      "log"
      "kotlin"
      "docker-compose"
      "basher"
      "ini"
      "haskell"
      "activitiwatch"
      "swift"
    ];
  };
}

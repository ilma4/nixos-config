{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}: let
  HOME = config.home.homeDirectory;
  inherit (pkgs) stdenv;
  isDarwin = stdenv.isDarwin;
  isGenericLinux = stdenv.isLinux && config.targets.genericLinux.enable;
  nixGenerationLink =
    if isGenericLinux
    then "${config.xdg.stateHome}/nix/profiles/home-manager"
    else "/run/current-system";
  homebrewPrefix =
    if osConfig != null && osConfig ? homebrew
    then osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix)
    else "/opt/homebrew";
  dircolorsConfigText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "${name} ${toString value}") config.programs.dircolors.settings
    ++ [""]
    ++ lib.optional (config.programs.dircolors.extraConfig != "") config.programs.dircolors.extraConfig
  );
  lsColorsShellSnippet = pkgs.runCommandLocal "i4-ls-colors.sh" {} ''
    set -euo pipefail
    ${lib.getExe' config.programs.dircolors.package "dircolors"} -b ${pkgs.writeText "dir_colors" dircolorsConfigText} > "$out"
  '';

  # Shell-integration snippets for direnv/fzf, precomputed at Nix build time
  # instead of being regenerated on every interactive shell.
  #
  # Home Manager normally wires these tools up with `eval "$(direnv hook zsh)"` /
  # `source <(fzf --zsh)`, which forks the tool binary on every startup. On macOS
  # a single fork+exec of a Nix-store binary costs ~6-9ms. Their generated output
  # depends only on the binary (a fixed store path), not on user config, so —
  # exactly like `lsColorsShellSnippet` above — we capture it once at build time
  # and `source` the static result, turning startup forks into cheap file reads.
  # `set -euo pipefail` per repo convention; both generators were verified to run
  # without $HOME, so the build stays hermetic.
  #
  # atuin is precomputed too (see atuinInitSnippet below). `atuin init zsh`
  # output DOES depend on atuin's config (e.g. the tmux popup integration emits
  # ATUIN_TMUX_POPUP*), so to keep the precomputed snippet faithful we now ship
  # the config itself in the Nix store (dotfiles/atuin/config.toml, deployed
  # read-only to ~/.config/atuin/config.toml) and generate the init against it.
  # Build-time config == deployed config by construction, so they can't diverge.

  # `direnv hook zsh` installs the precmd/chpwd hook that runs `direnv export`
  # on directory changes. The hook body is static (the per-prompt `direnv export`
  # still runs live, as it must); precomputing only removes the hook-generation
  # fork from startup.
  direnvHookSnippet = pkgs.runCommandLocal "i4-direnv-hook.zsh" {} ''
    set -euo pipefail
    ${lib.getExe' config.programs.direnv.package "direnv"} hook zsh > "$out"
  '';

  # `fzf --zsh` emits fzf's completion and key bindings (Ctrl-T, Ctrl-R, Alt-C).
  # Fully static output. Sourced before the atuin snippet (see initContent) so
  # atuin's Ctrl-R binding still wins, preserving the previous load order.
  # Output is a directory so the snippet can ship with its own .zwc: zsh's
  # `source <basename>` transparently loads an adjacent, not-older .zwc (Nix's
  # equal epoch mtimes count as not-older), turning the ~2-3ms parse into a
  # bytecode load — same mechanism that already speeds up p10kCompiledConfig.
  fzfInitSnippet = pkgs.runCommandLocal "i4-fzf-init" {} ''
    set -euo pipefail
    mkdir -p "$out"
    ${lib.getExe' config.programs.fzf.package "fzf"} --zsh > "$out/fzf-init.zsh"
    ${lib.getExe pkgs.zsh} -fc "zcompile -R -- '$out/fzf-init.zsh.zwc' '$out/fzf-init.zsh'"
  '';

  # `atuin init zsh` emits atuin's hooks and the Ctrl-R / up-arrow bindings. Its
  # output depends on atuin's config, so we point ATUIN_CONFIG_DIR at the same
  # store copy of config.toml that gets deployed to ~/.config/atuin (see
  # xdg.configFile below) — build-time and runtime config are then identical by
  # construction. The session block it emits (`export ATUIN_SESSION=$(atuin
  # uuid)`) is still guarded, so the fork-free ATUIN_SESSION pre-seed in the
  # `early` block keeps skipping that ~16ms `atuin uuid` fork; precomputing here
  # additionally removes the ~17ms `atuin init zsh` generation fork. The flags
  # mirror programs.atuin.flags (single source of truth). writableTmpDirAsHomeHook
  # gives atuin a writable HOME at build time (it best-effort mkdir's its data
  # dirs), matching Home Manager's own fish/nu init generators. Shipped as a dir
  # with an adjacent .zwc so `source <basename>` loads bytecode (see fzf above).
  atuinInitSnippet =
    pkgs.runCommandLocal "i4-atuin-init" {
      nativeBuildInputs = [pkgs.writableTmpDirAsHomeHook];
    } ''
      set -euo pipefail
      mkdir -p "$out"
      ATUIN_CONFIG_DIR=${../dotfiles/atuin} \
        ${lib.getExe' config.programs.atuin.package "atuin"} init zsh ${lib.escapeShellArgs config.programs.atuin.flags} > "$out/atuin-init.zsh"
      ${lib.getExe pkgs.zsh} -fc "zcompile -R -- '$out/atuin-init.zsh.zwc' '$out/atuin-init.zsh'"
    '';

  # Powerlevel10k ships source files and tries to zcompile them at runtime only
  # when its install directory is writable. The Nix store is intentionally not
  # writable, so copy the theme tree into a small derivation and precompile the
  # files that upstream would otherwise compile on first use.
  p10kCompiledTheme = pkgs.runCommandLocal "i4-powerlevel10k-compiled" {} ''
    set -euo pipefail
    cp -R -L ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k "$out"
    chmod -R u+w "$out"

    for p10k_file in \
      powerlevel9k.zsh-theme \
      powerlevel10k.zsh-theme \
      internal/p10k.zsh \
      internal/icons.zsh \
      internal/configure.zsh \
      internal/worker.zsh \
      internal/parser.zsh \
      gitstatus/gitstatus.plugin.zsh \
      gitstatus/install
    do
      if [[ -f "$out/$p10k_file" ]]; then
        ${lib.getExe pkgs.zsh} -fc "zcompile -R -- '$out/$p10k_file.zwc' '$out/$p10k_file'"
      fi
    done
  '';

  # Also precompile the user's P10K config. It is sourced as a script, so zsh
  # will automatically prefer the adjacent .zwc when it is at least as new as
  # the source file (true for Nix store outputs with normalized mtimes).
  p10kCompiledConfig = pkgs.runCommandLocal "i4-p10k-config-compiled" {} ''
    set -euo pipefail
    mkdir -p "$out"
    cp ${../dotfiles/p10k.zsh} "$out/p10k.zsh"
    chmod u+w "$out/p10k.zsh"
    ${lib.getExe pkgs.zsh} -fc "zcompile -R -- '$out/p10k.zsh.zwc' '$out/p10k.zsh'"
  '';

  # Fingerprint of the Nix-managed inputs that determine zsh's completion dump:
  # the zsh-completions package and the home profile, where Home Manager
  # installs each enabled program's completion functions. The
  # invalidateZcompdump activation script compares this against the last-applied
  # copy and drops ~/.zcompdump when it differs; see
  # programs.zsh.completionInit for why the dump is otherwise never rebuilt
  # (compinit -C).
  zcompdumpFingerprint = pkgs.writeText "i4-zcompdump-fingerprint" (lib.concatLines [
    "${pkgs.zsh-completions}"
    "${config.home.path}"
  ]);
in {
  config = lib.mkIf config.i4.base.enable {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      # Skip compinit's per-startup security audit (compaudit) and staleness
      # check; fpath only changes on nix-rebuild. The invalidateZcompdump
      # activation script below deletes the dump whenever the Nix-managed
      # completion set changes, so the next shell rebuilds it; a manual
      # `rm ~/.zcompdump*` is only needed for completions added outside Nix
      # (e.g. Homebrew on macOS).
      completionInit = ''
        autoload -U compinit && compinit -C -d "$HOME/.zcompdump"

        # Precompile the completion dump to bytecode. `compinit -C` loads the
        # dump but, unlike a full compinit, never (re)compiles it, so do it here
        # when the .zwc is missing or stale; the next startup's `. $dump` then
        # transparently loads the adjacent .zwc (~2ms faster). The stat tests
        # are builtins (no fork); the compile runs only on the first startup
        # after the dump changes (e.g. after `rm ~/.zcompdump*`). Write to a
        # temp then rename so a half-written .zwc can't be picked up if two
        # shells start at once. NB: the temp name MUST end in .zwc, else
        # `zcompile` appends .zwc itself and the rename would miss the file.
        if [[ -s "$HOME/.zcompdump" && ( ! -s "$HOME/.zcompdump.zwc" || "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ) ]]; then
          zcompile -R -- "$HOME/.zcompdump.$$.zwc" "$HOME/.zcompdump" 2>/dev/null &&
            mv -f "$HOME/.zcompdump.$$.zwc" "$HOME/.zcompdump.zwc" 2>/dev/null
        fi
      '';

      # oh-my-zsh was loaded only for the vi-mode plugin but cost ~190ms at
      # startup (framework sourcing + the compinit/compaudit it drives). Native
      # `bindkey -v` in initContent below replaces it.
      oh-my-zsh.enable = false;

      # Add Powerlevel10k theme and your custom config as plugins
      shellAliases = {
        ls = lib.mkIf isDarwin "${pkgs.coreutils}/bin/ls --color=auto"; # use GNU ls on macOS, it has better colors
        # dirsize = "${pkgs.ncdu}/bin/ncdu";
        l = "ls -lah";
        ll = "ls -lh";

        # Quick parent-directory navigation: `..` → up one level, each extra dot
        # goes one level higher, up to `.....` (5 dots) → up four levels.
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        "....." = "cd ../../../..";
      };

      initContent = let
        early = lib.mkOrder 500 ''
          fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)
          ${lib.optionalString isDarwin "fpath+=(${homebrewPrefix}/share/zsh/site-functions)"}

          # Pre-seed Powerlevel10k's SSH detection. p10k's _p9k_init_ssh forks
          # `who -m` (~13-19ms) on every startup whenever no SSH_* vars are set
          # — i.e. on every local shell — to cover the rare case of a remote
          # session that lost SSH_CONNECTION (e.g. `sudo -i`). Derive the same
          # flag from the environment ourselves (fork-free) and mark this TTY as
          # already-probed so _p9k_init_ssh early-returns at its guard. SSH_* is
          # accurate for every normal local and SSH session, so the prompt's ssh
          # segment still works on the servers that share this config (nas etc).
          if [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY ]]; then
            typeset -gix P9K_SSH=1
          else
            typeset -gix P9K_SSH=0
          fi
          typeset -gx _P9K_SSH_TTY=$TTY

          # Record the generation this shell was initialized against. NixOS and
          # nix-darwin expose it through /run/current-system, while standalone
          # Home Manager uses its per-user home-manager profile.
          # zstat is a zsh builtin, so checking it does not fork readlink.
          zmodload -F zsh/stat b:zstat
          typeset -g NIX_SHELL_GENERATION=
          if [[ -L ${lib.escapeShellArg nixGenerationLink} ]] &&
            zstat -A _nix_gen +link ${lib.escapeShellArg nixGenerationLink}
          then
            typeset -g NIX_SHELL_GENERATION=$_nix_gen[1]
          fi
          unset _nix_gen

          # Return success when the current generation differs from the
          # generation captured at shell startup.
          function nix-shell-stale {
            local -a gen
            [[ -n $NIX_SHELL_GENERATION && -L ${lib.escapeShellArg nixGenerationLink} ]] &&
              zstat -A gen +link ${lib.escapeShellArg nixGenerationLink} &&
              [[ $NIX_SHELL_GENERATION != $gen[1] ]]
          }

          # Pre-seed atuin's session id so Home Manager's later
          # `eval "$(atuin init zsh)"` skips its `export ATUIN_SESSION=$(atuin
          # uuid)` — that command substitution forks the ~16ms atuin binary on
          # every startup. atuin's init only runs it when ATUIN_SESSION is unset
          # or this is a new shell level, so we replicate that exact guard and
          # fill the var ourselves, fork-free. The value mimics `atuin uuid` (a
          # UUIDv7): 32 lowercase hex chars = a 48-bit millisecond timestamp +
          # $RANDOM, byte-for-byte the same format atuin emits, so it still
          # parses as a UUID downstream. The anon function scopes the temp;
          # printf is a builtin (no fork).
          if [[ -z ''${ATUIN_SESSION:-} || ''${ATUIN_SHLVL:-} != $SHLVL ]]; then
            zmodload zsh/datetime
            () {
              local -i ms=$(( EPOCHREALTIME * 1000 ))
              printf -v ATUIN_SESSION '%012x%04x%04x%04x%04x%04x' \
                $ms $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
            }
            export ATUIN_SESSION ATUIN_SHLVL=$SHLVL
          fi

          # Powerlevel10k theme (precompiled with zcompile in the let-block).
          source ${p10kCompiledTheme}/powerlevel10k.zsh-theme
          source ${p10kCompiledConfig}/p10k.zsh # Powerlevel10k config
        '';

        beforeCompinit = lib.mkOrder 550 ''
          ${lib.optionalString isDarwin ''
            # nix-darwin includes completions from /nix/var/nix/profiles/default,
            # which may resolve to a mixed-ownership store path on quicksilver.
            for default_profile_fpath in \
              /nix/var/nix/profiles/default/share/zsh/site-functions \
              /nix/var/nix/profiles/default/share/zsh/$ZSH_VERSION/functions \
              /nix/var/nix/profiles/default/share/zsh/vendor-completions
            do
              fpath=(''${fpath:#$default_profile_fpath})
            done
            unset default_profile_fpath
          ''}

          # Collapse fpath entries that resolve to the same directory. Nix can
          # expose zsh's builtin functions through several profile symlinks
          # ($HOME/.nix-profile, /run/current-system/sw, and the store path);
          # `typeset -U fpath` only removes exact string duplicates, so compinit
          # would otherwise scan and dump the same ~1k files multiple times.
          typeset -A i4_seen_fpath
          typeset -a i4_deduped_fpath
          for i4_fpath_dir in "''${fpath[@]}"; do
            if [[ -d $i4_fpath_dir ]]; then
              i4_fpath_key="''${i4_fpath_dir:A}"
            else
              i4_fpath_key="$i4_fpath_dir"
            fi

            [[ -n ''${i4_seen_fpath[$i4_fpath_key]-} ]] && continue
            i4_seen_fpath[$i4_fpath_key]=1
            i4_deduped_fpath+=("$i4_fpath_dir")
          done
          fpath=("''${i4_deduped_fpath[@]}")
          unset i4_seen_fpath i4_deduped_fpath i4_fpath_dir i4_fpath_key

          # LS_COLORS is computed by dircolors at Nix build time, so zsh only
          # sources a static assignment instead of spawning dircolors on every
          # interactive shell startup.
          source ${lsColorsShellSnippet}

          # Home Manager appends an unconditional `mkdir -p "$(dirname
          # "$HISTFILE")"` just after this block. $HISTFILE always lives in
          # $HOME (which exists), yet that line forks both `dirname` (~8ms) and
          # `mkdir` (~7ms) on every startup. Make `mkdir` a shell builtin and
          # shadow `dirname` with a :h expansion so the line runs fork-free.
          # Both are reverted in the `normal` block once HM's line has run, so
          # the interactive shell keeps the real external mkdir/dirname.
          zmodload -F zsh/files b:mkdir
          function dirname { print -r -- "''${1:h}" }
        '';

        normal = lib.mkOrder 1000 ''
          # Undo the fork-free shadows set up in beforeCompinit: Home Manager's
          # HISTFILE mkdir has run by now, so restore the external mkdir/dirname
          # for interactive use.
          zmodload -F zsh/files -b:mkdir 2>/dev/null
          unfunction dirname 2>/dev/null

          # Native vi mode (replaces the oh-my-zsh vi-mode plugin).
          bindkey -v

          # disable ZLE execute-named-cmd prompt (like ":" in normal mode in (neo)vim)
          bindkey -M vicmd ':' undefined-key

          # Backspace in insert mode should delete freely, not just within the
          # current insert session. After `bindkey -v`, viins binds Backspace to
          # `vi-backward-delete-char`, which (like historical vi) refuses to delete
          # past `viinsbegin` — the cursor position zsh records every time insert
          # mode is (re)entered. On a fresh prompt viinsbegin is 0, so Backspace
          # works everywhere; but after Esc then i/a/I/A/... it equals the cursor,
          # so an immediate Backspace has nothing to delete and is a no-op (you can
          # only erase characters typed since re-entering insert). backward-delete-char
          # has no such boundary, matching vim's `backspace=indent,eol,start`. Bind
          # both DEL (^?, sent by most terminals for Backspace) and BS (^H).
          bindkey -M viins '^?' backward-delete-char
          bindkey -M viins '^h' backward-delete-char

          # Delay after seeing the Esc character before ZLE treats it as a
          # lone Esc (units are centiseconds). Default to 1 (10ms) locally;
          # over SSH raise to 10 (100ms) so network latency doesn't split a
          # multi-byte escape sequence (e.g. an arrow key) into a bare Esc
          # plus stray characters. Same SSH probe as the P9K_SSH pre-seed.
          if [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY ]]; then
            export KEYTIMEOUT=10
          else
            export KEYTIMEOUT=1
          fi

          # Remote tmux (extended-keys on, see programs.tmux below) switches the
          # LOCAL terminal into an extended-keys mode via the ssh byte stream.
          # tmux disables it again on clean detach, but when the connection dies
          # abruptly (network loss, server reboot, `~.`) nothing does, and the
          # terminal is left with broken hotkeys. Reset the mode whenever ssh
          # exits: the `always` block runs even when ssh is interrupted and
          # keeps ssh's exit status. \e[>4;0m resets xterm modifyOtherKeys
          # (iTerm2); \e[=0;1u zeroes kitty keyboard-protocol flags (kitty
          # doesn't implement modifyOtherKeys). Each terminal ignores the
          # sequence it doesn't support. Skipped inside tmux: there the bytes
          # would disable extended keys for the surrounding pane, and tmux
          # already restores the outer terminal itself when it detaches or
          # exits. Relies on the ServerAliveInterval keepalive in
          # programs.ssh: without it a dead connection leaves ssh hanging and
          # no reset ever runs.
          function ssh {
            {
              command ssh "$@"
            } always {
              [[ -t 1 && -z $TMUX ]] && printf '\033[>4;0m\033[=0;1u'
            }
          }

          # Report the running command as the terminal title, falling back to
          # the current directory's name whenever zsh is waiting at a prompt.
          # preexec's second argument is the alias-expanded command; tokenize it
          # with zsh's `(z)` flag and show only the executable's basename, which
          # avoids leaking command arguments into the title. The OSC `\e]0;…\a`
          # escape sets both the icon name and window/tab title, which terminal
          # emulators show as the session name and tmux uses as the window name.
          # `print -P` expands %1~ to the last path component while preserving ~
          # / ~user named-directory substitution. Everything here is a builtin.
          autoload -Uz add-zsh-hook
          function i4-set-term-title { print -Pn '\e]0;%1~\a' }
          function i4-set-term-title-command {
            local -a i4_command_words
            i4_command_words=("''${(@z)2}")
            [[ -n ''${i4_command_words[1]-} ]] &&
              print -rn -- $'\e]0;'"''${i4_command_words[1]:t}"$'\a'
          }
          add-zsh-hook precmd i4-set-term-title
          add-zsh-hook preexec i4-set-term-title-command


          ## Arrow up/down behavior like in oh-my-zsh (search by prefix)
          autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
          zle -N up-line-or-beginning-search
          zle -N down-line-or-beginning-search

          # Normal terminal arrow sequences
          bindkey -M viins '^[[A' up-line-or-beginning-search
          bindkey -M viins '^[[B' down-line-or-beginning-search

          # Sometimes used by terminals via terminfo
          zmodload zsh/terminfo
          [[ -n "''${terminfo[kcuu1]}" ]] && bindkey -M viins "''${terminfo[kcuu1]}" up-line-or-beginning-search
          [[ -n "''${terminfo[kcud1]}" ]] && bindkey -M viins "''${terminfo[kcud1]}" down-line-or-beginning-search


          # Integrate vi-mode yank/put with the system clipboard. On Linux, SSH
          # sessions always use OSC 52 so clipboard traffic reaches the local
          # terminal; non-SSH sessions use the Wayland clipboard. macOS always
          # uses its native pbcopy/pbpaste tools.
          ${
            if isDarwin
            then ''
              # macOS always ships pbcopy/pbpaste, so bind them directly. Done
              # without a $+commands probe on purpose: that probe forces zsh to
              # build the full command hash (a $PATH scan, ~2ms) during startup;
              # skipping it defers the scan to first completion/command use.
              function _clip_copy { pbcopy }
              function _clip_paste { pbpaste }
            ''
            else ''
              if [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY ]]; then
                function _clip_copy { osc copy }
                function _clip_paste { osc paste }
              else
                function _clip_copy { wl-copy }
                function _clip_paste { wl-paste --no-newline }
              fi
            ''
          }

          if (( $+functions[_clip_copy] )); then
            function vi-yank-clip { zle vi-yank; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-yank-eol-clip { zle vi-yank-eol; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-delete-clip { zle vi-delete; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-put-after-clip { CUTBUFFER="$(_clip_paste)"; zle vi-put-after }
            function vi-put-before-clip { CUTBUFFER="$(_clip_paste)"; zle vi-put-before }
            zle -N vi-yank-clip
            zle -N vi-yank-eol-clip
            zle -N vi-delete-clip
            zle -N vi-put-after-clip
            zle -N vi-put-before-clip
            bindkey -M vicmd 'y' vi-yank-clip
            bindkey -M vicmd 'Y' vi-yank-eol-clip
            bindkey -M vicmd 'd' vi-delete-clip
            bindkey -M vicmd 'p' vi-put-after-clip
            bindkey -M vicmd 'P' vi-put-before-clip
            bindkey -M visual 'y' vi-yank-clip
          fi

          # Completion: colorize file listings using precomputed LS_COLORS, and
          # show an interactive menu that highlights the currently selected item.
          zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
          zstyle ':completion:*' menu select
          # Shift+Tab sends the terminal's back-tab sequence.
          bindkey -M viins '^[[Z' reverse-menu-complete
          # Case-insensitive matching: lowercase input matches both cases, so
          # `foo<tab>` completes `Foo`/`FOO` too. Uppercase input stays exact.
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

          # direnv/fzf/atuin integrations, precomputed at build time (see the
          # *Snippet derivations in the let-block). Each is sourced only when its
          # program is enabled, mirroring Home Manager (which emits an integration
          # only for an enabled program). The guard matters for direnv: it is
          # enabled only via home/dev.nix behind i4.dev.enable, so sourcing it
          # unconditionally would start running direnv on every prompt on hosts
          # (e.g. nas, msi-modern) that never opted in. enableZshIntegration is
          # false for all three, so these static sources replace HM's own
          # per-startup `direnv hook` / `fzf --zsh` / `atuin init zsh` forks. Runs
          # after compinit (HM emits that earlier).
          ${lib.optionalString config.programs.direnv.enable "source ${direnvHookSnippet}"}

          # fzf defines ZLE widgets, so guard on the line editor being active
          # (mirrors HM's `$options[zle]` guard).
          ${lib.optionalString config.programs.fzf.enable ''
            if [[ $options[zle] = on ]]; then
              source ${fzfInitSnippet}/fzf-init.zsh
            fi
          ''}

          # atuin is sourced AFTER fzf so its Ctrl-R binding wins, exactly as
          # before when HM appended its own `eval "$(atuin init zsh)"` after this
          # block — only now it's a static, zcompiled source with no startup fork.
          # The `$options[zle]` guard mirrors HM's wrapper.
          ${lib.optionalString config.programs.atuin.enable ''
            if [[ $options[zle] = on ]]; then
              source ${atuinInitSnippet}/atuin-init.zsh
            fi
          ''}
        '';
      in
        lib.mkMerge [early normal beforeCompinit];

      # Fix ssh agent forwarding when reattaching to screen from new ssh connection
      profileExtra =
        lib.mkIf (stdenv.isLinux && config.configure-ssh) # macOS works fine with ssh agent

        ''
          if [ -n "''${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] && [ ! -h "$SSH_AUTH_SOCK" ]; then
              mkdir -p ${HOME}/.ssh
              ln -sf "$SSH_AUTH_SOCK" ${HOME}/.ssh/ssh_auth_sock
          fi

          if [ -S ${HOME}/.ssh/ssh_auth_sock ]; then
              export SSH_AUTH_SOCK=${HOME}/.ssh/ssh_auth_sock
          fi
        '';
    };

    # Invalidate the zsh completion dump when the Nix-managed completion set
    # changes. compinit -C (see programs.zsh.completionInit) never rebuilds the
    # dump on its own, so without this newly added completions would not appear
    # until ~/.zcompdump was deleted by hand. Comparing a fingerprint instead of
    # deleting unconditionally keeps the dump cached across rebuilds that don't
    # touch completions, preserving the startup-time win it provides. The
    # fingerprint is installed (not echoed) so $DRY_RUN_CMD makes `--dry-run` a
    # true no-op.
    home.activation.invalidateZcompdump = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if ! ${lib.getExe' pkgs.diffutils "cmp"} -s ${zcompdumpFingerprint} "$HOME/.zcompdump.fingerprint" 2>/dev/null; then
        $DRY_RUN_CMD rm -f $VERBOSE_ARG "$HOME/.zcompdump" "$HOME/.zcompdump.zwc"
        $DRY_RUN_CMD install $VERBOSE_ARG -m644 ${zcompdumpFingerprint} "$HOME/.zcompdump.fingerprint"
      fi
    '';

  };
}

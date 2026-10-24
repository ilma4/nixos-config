final: _prev: {
  dekit = final.rustPlatform.buildRustPackage (finalAttrs: {
    pname = "dekit";
    version = "0.10.2";
    __structuredAttrs = true;

    src = final.fetchFromGitHub {
      owner = "pvolok";
      repo = "dekit";
      tag = "v${finalAttrs.version}";
      hash = "sha256-4EcWcYnL9Ua9pQ0K8hIRLVOcHfK3V9T9LS0LDVpH0dw=";
    };

    cargoHash = "sha256-0fLXXJouIOy/8fcKhneEYIuGj3EzTL+owSVEEsxGNRg=";

    nativeCheckInputs = [final.curl];

    # Upstream 0.10.2 documents std.tui members absent from the test runtime.
    checkFlags =
      ["--skip=help::tests::every_js_member_has_a_record"]
      # Times out waiting for ready-command warnings in the Darwin sandbox.
      ++ final.lib.optional final.stdenv.hostPlatform.isDarwin "--skip=commands_that_cannot_run_are_reported";

    nativeInstallCheckInputs = [final.versionCheckHook];
    doInstallCheck = true;

    passthru.updateScript = final.nix-update-script {};

    meta = {
      description = "Process manager for dev and prod";
      homepage = "https://github.com/pvolok/dekit";
      changelog = "https://github.com/pvolok/dekit/releases/tag/v${finalAttrs.version}";
      license = final.lib.licenses.mit;
      platforms = final.lib.platforms.unix;
      mainProgram = "dekit";
    };
  });
}

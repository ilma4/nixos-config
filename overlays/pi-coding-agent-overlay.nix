final: prev: {
  pi-coding-agent = final.buildNpmPackage rec {
    pname = "pi-coding-agent";
    version = "0.54.0";

    src = final.fetchFromGitHub {
      owner = "badlogic";
      repo = "pi-mono";
      rev = "v${version}";
      hash = "sha256-j8h8KKt/1m47Y6/KA8g213gooq0n2fAqBVkKhHsBCGw=";
    };

    # Fix lockfile metadata before vendoring dependencies.
    postPatch = ''
      ${final.npm-lockfile-fix}/bin/npm-lockfile-fix package-lock.json
    '';

    npmDepsHash = "sha256-vVrpfSavccWafuzKo57C5Kfk/nJcWL3Num+FFZ1oTkI=";
    npmWorkspace = "packages/coding-agent";
    npmInstallFlags = ["--ignore-scripts"];
    npmRebuildFlags = ["--ignore-scripts"];

    # Build local workspace dependencies required by pi-coding-agent,
    # but avoid the pi-ai network-based model generation step.
    preBuild = ''
      npm run --workspace=packages/tui build
      npm exec --workspace=packages/ai -- tsgo -p tsconfig.build.json
      npm run --workspace=packages/agent build
    '';

    npmPackFlags = ["--ignore-scripts"];
    nodejs = final.nodejs_22;

    postInstall = ''
      packageRoot="$out/lib/node_modules/pi-monorepo"
      mkdir -p "$packageRoot/packages"

      # Populate workspace package paths required by linked dependencies.
      for workspace in ai agent tui coding-agent; do
        cp -r "packages/$workspace" "$packageRoot/packages/$workspace"
      done

      # Remove any leftover dangling workspace links that are not needed.
      find "$packageRoot/node_modules" -type l | while IFS= read -r link; do
        if [ ! -e "$link" ]; then
          rm "$link"
        fi
      done
    '';

    meta = with final.lib; {
      description = "Interactive coding agent CLI";
      homepage = "https://github.com/badlogic/pi-mono";
      license = licenses.mit;
      mainProgram = "pi";
      platforms = platforms.all;
    };
  };
}

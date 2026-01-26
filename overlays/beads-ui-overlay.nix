final: prev: {
  beads-ui = final.buildNpmPackage rec {
    pname = "beads-ui";
    version = "0.9.3";

    src = final.fetchFromGitHub {
      owner = "mantoni";
      repo = "beads-ui";
      rev = "v${version}";
      hash = "sha256-mgNnDDsp4gfCiRobXLMqMzzsdjrAQOwdwJYgnYyxRBI=";
    };

    # Fix lockfile before npm vendoring/build.
    postPatch = ''
      ${final.npm-lockfile-fix}/bin/npm-lockfile-fix package-lock.json
    '';

    npmLockfile = "${src}/package-lock.json";

    npmDepsHash = "sha256-n9nN4Jlz2BgCycMNi4A7Yl45RFqkE/nCgu++yESU5e4=";

    # Fix
    npmPackFlags = ["--ignore-scripts"];

    nodejs = final.nodejs_22;

    meta = with final.lib; {
      description = "Local UI for Beads — Collaborate on issues with your coding agent.";
      homepage = "https://github.com/mantoni/beads-ui";
      license = licenses.mit;
      mainProgram = "bdui";
      platforms = platforms.all;
    };
  };
}

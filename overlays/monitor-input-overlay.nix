final: prev: {
  monitor-input = let
    customRustPlatform = final.makeRustPlatform {
      cargo = final.rust-bin.stable.latest.default;
      rustc = final.rust-bin.stable.latest.default;
    };
  in customRustPlatform.buildRustPackage rec {
    pname = "monitor-input";
    version = "4334fdd373a22d15c90908406f269a8d83871214";

    src = final.fetchFromGitHub {
      owner = "kojiishi";
      repo = "monitor-input-rs";
      rev = version;
      hash = "sha256-CW++0VprTswB8o7wK32p3XC4xo064i7vCn0rSGNxOXA=";
    };

    cargoHash = "sha256-iRNDHmrD592Sc/HQ7AbF1CwQlBvK/0TkrnBtkqnT1Q4=";

    # runtime dependencies
    buildInputs = final.lib.optionals final.stdenv.isLinux [
      final.systemd
    ];

    meta = with final.lib; {
      description = "Control monitor input sources";
      homepage = "https://github.com/kojiishi/monitor-input-rs";
      license = licenses.mit;
      mainProgram = "monitor-input";
      platforms = platforms.all;
    };
  };
}
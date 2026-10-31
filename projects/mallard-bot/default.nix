{pkgs}: let
  inherit (pkgs) lib;
  dependencies = ps: [
    ps.python-telegram-bot
    ps.numpy
    ps.pillow
    ps.opencv-python-headless
  ];
  python = pkgs.python314.withPackages dependencies;
  testPython = pkgs.python314.withPackages (ps: dependencies ps ++ [ps.pytest]);
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      lib.cleanSourceFilter path type
      && !(builtins.elem (baseNameOf path) [".venv" ".pytest_cache" "__pycache__" ".github"])
      && !(lib.hasSuffix ".pyc" path);
  };
in {
  inherit src;

  devShell = pkgs.mkShell {
    packages = [testPython pkgs.ffmpeg-headless];
    PYTHONNOUSERSITE = "1";
    PYTHONDONTWRITEBYTECODE = "1";
  };

  image = pkgs.dockerTools.buildLayeredImage {
    name = "localhost/mallard-bot";
    compressor = "zstd"; # zstd defaults to compression level 3.
    contents = [
      python
      pkgs.ffmpeg-headless
      pkgs.dockerTools.binSh
      pkgs.dockerTools.caCertificates
    ];
    extraCommands = ''
      set -euo pipefail
      mkdir -p app tmp
      cp -R ${src}/. app/
      chmod 1777 tmp
    '';
    config = {
      WorkingDir = "/app";
      Cmd = ["${python}/bin/python3" "app.py"];
      Env = [
        "PATH=${lib.makeBinPath [python pkgs.ffmpeg-headless]}"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        "PYTHONNOUSERSITE=1"
        "PYTHONDONTWRITEBYTECODE=1"
        "PYTHONUNBUFFERED=1"
      ];
    };
  };
}

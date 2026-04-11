final: _prev: {
  restic-exporter = final.buildGoModule rec {
    pname = "restic-exporter";
    version = "1.0.0";

    src = final.fetchFromGitHub {
      owner = "josh";
      repo = "restic-exporter";
      rev = "v${version}";
      hash = "sha256-dATC76vMixVh38TEvOZAHhN/xSxdaZxCxBI0BhsvSWs=";
    };

    vendorHash = "sha256-22l/3wEJ7wMsvfEFRjuCxVYh+sTCp9yUQRqQ6ZhoDCM=";
    doCheck = false;

    ldflags = [
      "-s"
      "-w"
      "-X main.version=v${version}"
    ];

    meta = with final.lib; {
      description = "Prometheus exporter for Restic metrics";
      homepage = "https://github.com/josh/restic-exporter";
      license = licenses.mit;
      mainProgram = "restic-exporter";
      platforms = platforms.all;
    };
  };
}

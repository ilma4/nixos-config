final: prev: {
  paperless-mcp = final.buildNpmPackage rec {
    pname = "paperless-mcp";
    version = "0.4.1";

    src = final.fetchFromGitHub {
      owner = "baruchiro";
      repo = "paperless-mcp";
      rev = "5ad68b6b3ea80c7f5701968a177e74352645c7a4";
      hash = "sha256-B8r9inWQ40etyL7WxD+uuHQXgwwaJWlHE/QCZca6Zbc=";
    };

    npmDepsHash = "sha256-wgka/5S9EHQliYBjHsV0+p8vRU8vjX0qy1fdYsu08EM=";

    npmPackFlags = ["--ignore-scripts"];
    nodejs = final.nodejs_24;

    meta = with final.lib; {
      description = "MCP server for Paperless-NGX";
      homepage = "https://github.com/baruchiro/paperless-mcp";
      license = licenses.isc;
      mainProgram = "paperless-mcp";
      platforms = platforms.all;
    };
  };
}

final: prev: let
  rev = "0462fc55bcbcdc735e62feb5d1e5225b13420bd7";
in {
  htop = prev.htop.overrideAttrs (oldAttrs: {
    version = "${oldAttrs.version}-unstable-${builtins.substring 0 7 rev}";
    src = final.fetchFromGitHub {
      owner = "htop-dev";
      repo = "htop";
      inherit rev;
      hash = "sha256-ynGk5omcfKVccHzksZPWqAjR9FKXc/GcHhiAvNg8xkQ=";
    };
    meta =
      oldAttrs.meta
      // {
        changelog = "https://github.com/htop-dev/htop/commits/${rev}";
      };
  });
}

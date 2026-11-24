{pkgs, inputs}:
# Keep the newer Git on Darwin without pulling in the unstable Python and
# compiler toolchain or overriding Git for unrelated nixpkgs packages.
if pkgs.stdenv.hostPlatform.isDarwin
then pkgs.callPackage (inputs.nixpkgs-unstable + "/pkgs/by-name/gi/git/package.nix") {}
else pkgs.git

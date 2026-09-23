{pkgs}: let
  # Revisions match the reftable-capable gitstatus Homebrew formula.
  reftableLibgit2 = pkgs.libgit2.overrideAttrs (_: {
    src = pkgs.fetchFromGitHub {
      owner = "libgit2";
      repo = "libgit2";
      rev = "44c05e5d12f2b8b86b9730bb50f27daf74143782";
      hash = "sha256-57fpOm7DtVAS/NlQPa4FcL1kd6GuJGfYotzCOtrg8PA=";
    };
    doCheck = false;
  });
in
  pkgs.gitstatus.overrideAttrs (_: {
    src = pkgs.fetchFromGitHub {
      owner = "simnalamburt";
      repo = "gitstatus";
      rev = "fbca4a5a589b991f9cc4b24306d270558f56812d";
      hash = "sha256-Q+4FIb5N59x1pcQR9uwMxQa+hKEHnWuKqTIhsHs2kIM=";
    };
    buildInputs = [reftableLibgit2 pkgs.zlib];
  })

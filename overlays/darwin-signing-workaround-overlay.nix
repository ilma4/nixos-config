final: prev: {
  fish = prev.fish.overrideAttrs (_old: {
    # Bust the cache key to force a local rebuild, ensuring valid codesigning
    # on Apple Silicon. See: https://github.com/NixOS/nixpkgs/issues/507531
    NIX_FORCE_LOCAL_REBUILD = "darwin-codesign-fix";
  });
  ffmpeg = prev.ffmpeg.overrideAttrs (_old: {
    # Bust the cache key to force a local rebuild, ensuring valid codesigning
    NIX_FORCE_LOCAL_REBUILD = "darwin-codesign-fix";
  });
}

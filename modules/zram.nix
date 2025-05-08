{...}: {
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    algorithm = "zstd";
  };
}

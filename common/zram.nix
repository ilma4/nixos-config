# TODO: Example module, remove
{ ... }:
{ 
  imports = [] ;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
    algorithm = "zstd";
  };
}


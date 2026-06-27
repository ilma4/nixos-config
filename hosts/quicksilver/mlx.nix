{
  homebrew = {
    taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
        trusted = true;
      }
    ];
    brews = [
      "jundot/omlx/omlx"
    ];
  };
}

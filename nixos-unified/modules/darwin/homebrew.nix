{
  homebrew = {
    enable = false;
    onActivation = {
      # autoUpdate = true;
      # upgrade = true;
      extraFlags = [
        "--verbose"
      ];
    };
    brews = [ ];
  };
}

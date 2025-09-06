{
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      extraFlags = [
        "--verbose"
      ];
    };
    casks = [
      "vivaldi"
    ];
    brews = [
      "media-control"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

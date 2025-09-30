{
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  homebrew = {
    enable = true;

    onActivation = {
      upgrade = true;
      autoUpdate = true;
      extraFlags = [
        "--verbose"
      ];
    };

    casks = [
      "huly"
      "vivaldi"
      "arduino-cli"
    ];

    brews = [
      "glab"
      "media-control"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

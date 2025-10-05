{
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # eval "$(/opt/homebrew/bin/brew shellenv)"
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
      "arduino-ide"
    ];

    brews = [
      "glab"
      "arduino-cli"
      "media-control"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

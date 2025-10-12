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
      "leader-key"
      "arduino-ide"
      "autoraiseapp"
      "karabiner-elements"
    ];

    brews = [
      "qemu"
      "glab"
      "kanata"
      "arduino-cli"
      "media-control"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

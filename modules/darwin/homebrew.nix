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

    global = {
      autoUpdate = true;
    };

    casks = [
      "huly"
      "vivaldi"
      "leader-key"
      "arduino-ide"
      "autoraiseapp"
      "docker-desktop"
      "karabiner-elements"
    ];

    # whalebrews = [
    #   "kilted-ros-base-noble"
    # ];

    brews = [
      "qemu"
      "glab"
      "kanata"
      # "whalebrew"
      "arduino-cli"
      "media-control"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

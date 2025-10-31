{
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # eval "$(/opt/homebrew/bin/brew shellenv)"
  homebrew = {
    enable = true;

    onActivation = {
      upgrade = true;
      cleanup = "zap";
      autoUpdate = true;
      extraFlags = [
        "--verbose"
      ];
    };

    global = {
      autoUpdate = true;
    };

    casks = [
      "via"
      "vial"
      "huly"
      "vivaldi"
      "unity-hub"
      "leader-key"
      "arduino-ide"
      # "autoraiseapp"
      "docker-desktop"
      "visual-studio-code"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      "qemu"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

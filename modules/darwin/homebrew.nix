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
      "sonic-pi"
      "unity-hub"
      "coderabbit"
      "leader-key"
      "arduino-ide"
      "supercollider"
      # "autoraiseapp"
      "docker-desktop"
      "visual-studio-code"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      "qemu"
      "avr-gcc"
      "arm-none-eabi-gcc"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ];
  };
}

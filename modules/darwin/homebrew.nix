{
  pkgs,
  lib,
  ...
}:
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
      "coderabbit"
      "tailscale-app"
      # "autoraiseapp"
      "visual-studio-code"
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "sonic-pi"
      "unity-hub"
      "leader-key"
      "arduino-ide"
      "supercollider"
      "docker-desktop"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "qemu"
      "avr-gcc"
      "arm-none-eabi-gcc"
    ];
  };
}

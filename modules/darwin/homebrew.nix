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

    global.autoUpdate = true;

    casks = [
      "via"
      "vial"
      "vivaldi"
      "coderabbit"
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "huly"
      # "comfyui"
      # "sonic-pi"
      "unity-hub"
      "leader-key"
      # "arduino-ide"
      "tailscale-app"
      # "supercollider"
      "docker-desktop"
      "visual-studio-code"
      # "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "qemu"
      "ferron"
      # "podman"
      "avr-gcc"
      "arm-none-eabi-gcc"
    ];
  };
}

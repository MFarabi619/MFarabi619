{
  lib,
  pkgs,
  ...
}:
{
  # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # eval "$(/opt/homebrew/bin/brew shellenv)"
  homebrew = {
    enable = true;
    global.autoUpdate = true;

    onActivation = {
      upgrade = true;
      cleanup = "zap";
      autoUpdate = true;

      extraFlags = [
        "--verbose"
      ];
    };

    casks = [
      "via"
      "vial"
      "vivaldi"
      "coderabbit"
      "binary-ninja-free"
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
      "gcc-arm-embedded"
      "visual-studio-code"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      "dirien/dirien/lazy-pulumi"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "qemu"
      "ferron" # rust-based caddy-like web server
      # "podman"
      # "avr-gcc"
      # "arm-none-eabi-gcc"
      "Vaishnav-Sabari-Girish/taps/comchan" # TUI serial monitor
    ];
  };
}

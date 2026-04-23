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
    enableZshIntegration = true;
    enableBashIntegration = true;

    onActivation = {
      upgrade = true;
      cleanup = "zap";
      autoUpdate = true;
      # extraFlags = [ "--verbose" ];
    };

    taps = [
      "espressif/eim"
    ];

    casks = [
      "via"
      "vial"
      "vivaldi"
      "coderabbit"
      "binary-ninja-free"
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "huly"
      "eim-gui"
      # "comfyui"
      # "sonic-pi"
      # "unity-hub"
      "leader-key"
      "claude-code"
      "tailscale-app"
      # "supercollider"
      "docker-desktop"
      "gcc-arm-embedded"
      "visual-studio-code"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];

    brews = [
      # "rust"
      "pulumi"
      "libvirt" # brew services start libvirt
      "pioarduino/pioarduino/pioarduino"
      # "dirien/dirien/lazy-pulumi"
      "Valkyrie00/homebrew-bbrew/bbrew" # homebrew TUI
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "eim"
      "mlx"
      "west"
      "qemu"
      "nemu"
      "stlink"
      "ollama"
      "ferron" # rust-based caddy-like web server
      "netscanner"
      # "podman"
      # "avr-gcc"
      # "arm-none-eabi-gcc"
      "renode/tap/renode-nightly"
      "Vaishnav-Sabari-Girish/taps/comchan" # TUI serial monitor
    ];
  };
}

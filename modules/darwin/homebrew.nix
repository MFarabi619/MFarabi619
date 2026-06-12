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
    greedyCasks = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    onActivation = {
      upgrade = true;
      cleanup = "zap";
      autoUpdate = true;
      # extraFlags = [ "--verbose" ];
    };

    taps = [
      "quickemu-project/quickemu"
    ];

    casks = [
      "via"
      "vial"
      "vivaldi"
      "coderabbit"
      "binary-ninja-free"
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
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
      "quickemu"
      "dfu-util"
      "galaxy-io/tap/gnat"
      # "dirien/dirien/lazy-pulumi"
      "Valkyrie00/homebrew-bbrew/bbrew"
      "pioarduino/pioarduino/pioarduino"
    ]
    ++ lib.optionals (pkgs.stdenv.isAarch64) [
      "mlx"
      "qemu"
      "nemu"
      "stlink"
      "ollama"
      "ferron" # rust-based caddy-like web server
      "netscanner"
      "u-boot-tools"
      "espressif/eim/eim"
      "renode/tap/renode-nightly"
      "Vaishnav-Sabari-Girish/taps/comchan" # TUI serial monitor
    ];
  };
}

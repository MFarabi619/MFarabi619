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
      autoUpdate = true;
      cleanup = "uninstall";
      # extraFlags = [ "--verbose" ];
    };

    cargoPackages = [
      "espup"
      "comchan"
      "mcumgrctl"
      "cargo-binstall"
      "wasm-bindgen-cli"
    ];

    # taps = [ "quickemu-project/quickemu" ];

    brews = [
      "rust"
      "rustup" # rustup toolchain link system "$(brew --prefix rust)"
      "pulumi"
      "libvirt" # brew services start libvirt
      # "quickemu"
      "dfu-util"
      # "galaxy-io/tap/gnat" # NATS tui
      "atopile/tap/atopile"
      "Valkyrie00/homebrew-bbrew/bbrew"
    ]
    ++ lib.optionals pkgs.stdenv.isAarch64 [
      "zig"
      "mlx"
      "qemu"
      "nemu"
      "SDL2"
      "ollama"
      "libgcrypt"
      # "ferron" # rust-based caddy-like web server
      "netscanner"
      "u-boot-tools"
      "espressif/eim/eim"
      # "renode/tap/renode-nightly"
    ];

    casks = [
      "vivaldi"
      "binary-ninja-free"
    ]
    ++ lib.optionals pkgs.stdenv.isAarch64 [
      "leader-key"
      "claude-code"
      "tailscale-app"
      "docker-desktop"
      "gcc-arm-embedded"
      "visual-studio-code"
      "raspberry-pi-imager"
      "silicon-labs-vcp-driver"
    ];
  };
}

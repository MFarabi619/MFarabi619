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
      "zig"
      "rust"
      "rustup" # rustup toolchain link system "$(brew --prefix rust)"
      "pulumi"
      "atopile/tap/atopile"
    ]
    ++ [
      "dfu-util"
      "u-boot-tools"
      "espressif/eim/eim"
    ]
    ++ [
      "mlx"
      "qemu"
      "nemu"
      "libvirt" # brew services start libvirt
      # "quickemu"
      # "galaxy-io/tap/gnat" # NATS tui
      # "renode/tap/renode-nightly"
      # "ferron" # rust-based caddy-like web server
    ]
    ++ [
      "SDL2"
      "ollama"
      "libgcrypt"
      "netscanner"
      "Valkyrie00/homebrew-bbrew/bbrew"
    ];

    casks = [
      "freecad"
      "vivaldi"
      "binary-ninja-free"
    ]
    ++ [
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

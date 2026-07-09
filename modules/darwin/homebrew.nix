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
    ]
    ++ [
      "dfu-util"
      "u-boot-tools"
      "espressif/eim/eim"
    ]
    ++ [
      "mlx"
      "ollama"
    ]
    ++ [
      "qemu"
      "nemu"
      "libvirt" # brew services start libvirt
      # "quickemu"
      # "galaxy-io/tap/gnat" # NATS tui
      # "renode/tap/renode-nightly"
      # "ferron" # rust-based caddy-like web server
    ]
    ++ [
      "f3d"
      "SDL2"
      "libgcrypt"
      "netscanner"
      "opencascade"
      "atopile/tap/atopile"
      "Valkyrie00/homebrew-bbrew/bbrew"
    ];

    casks = [
      "freecad"
      "vivaldi"
      "claude-code"
      "tailscale-app"
      "docker-desktop"
      "visual-studio-code"
      "raspberry-pi-imager"
    ]
    ++ [
      "gcc-arm-embedded"
      "binary-ninja-free"
      "silicon-labs-vcp-driver"
      "wch-ch34x-usb-serial-driver"
    ]
    ++ [ "leader-key" ];
  };
}

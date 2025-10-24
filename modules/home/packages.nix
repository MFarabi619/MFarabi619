# hygg # TUI book reader
# pog
# uvx parllama
# uvx netshow
# uvx exosphere
# cargo-selector
# systemd-manager-tui
# tewi
# ssh-para
# terminaltexteffects
# nemu
# doxx
# hwinfo-tui
# fnug
# godap
# jwt-tui
# mcp-probe
# mcp-nixos
# bagels
# moneyterm
# ticker
# mqtttui
# taproom
# tuistash
# arduino-cli-interactive # github.com/Vaishnav-Sabari-Girish/arduino-cli-interactive?ref=terminaltrove
# ballast
# calcure
# duf
# goto
# sshclick
# hostctl
# lssh
# neoss
# nap
# pinix
# lazy-etherscan
# chamber
# tick-rs
{
  pkgs,
  lib,
  ...
}:
{
  home = {
    packages =
      with pkgs;
      [
        tree
        pnpm
        gnutls           # TLS connectivity
        # =============
        # kicad
        # logseq
        openscad
        openscad-lsp
        # =============
        vips             # dired image previews
        imagemagick      # for image-dired
        poppler-utils    # dired pdf previews
        epub-thumbnailer # dired epub previews
        # =============
        tuntox           # collab
        sqlite           # :tools lookup & :lang org +roam
        ispell           # spelling
        gnuplot
        shellcheck       # shell script formatting
        octaveFull       # gnu octave
        mermaid-cli      # mermaid diagram support
        # ============= 🧑‍💻🐞✨‍ ================
        # tsui # tailscale tui, not on nixpkgs yet | curl -fsSL https://neuralink.com/tsui/install.sh | bash
        nmap
        tgpt
        pik              # local port tui
        sshs             # ssh tui
        gpg-tui
        termscp
        caligula         # disk imaging
        keymapviz        # visualize keyboard layout in ascii
        tcpdump
        cointop          # crypto price feed
        wiki-tui
        bandwhich
        cargo-seek
        nvtopPackages.full # btop for gpu

        # leetcode-tui

        # keymap-drawer # visualize keyboard layout

        # lazyhetzner

        gama-tui        # github actions runners
        codeberg-cli

        vi-mongo        # mongodb tui

        presenterm

        wireshark-cli

        stylelint
        # ============= ‍❄🕸 ================
        nil         # nix formatter
        omnix
        devenv
        cachix
        nix-du      # store visualizer
        # nix-ld      # run unpatched dynamic binaries
        nix-btm     # nix process monitor
        nix-top     # nix process visualizer
        nix-web     # web gui
        nix-info
        # mcp-nixos # mcp server for NixOS
        nix-health  # health check
        nix-inspect # flake explorer tui
        nix-weather # check binary cache availability

        # ============= 🤖 ==================
        cmake       # vterm compilation and more
        gnumake
        coreutils
        platformio
        arduino-cli
        arduino-language-server

        # fritzing

        # Setup Claude Code using Google Vertex AI Platform
        # https://github.com/juspay/vertex
        # flake.inputs.vertex.packages.${system}.default

        # ============== 🤪 =================
        genact
        smassh       # TUI monkeytype
        cowsay       # ascii cow
        lolcat       # rainbow text output
        figlet       # fancy ascii text output
        cmatrix      # matrix animation
        nyancat      # rainbow flying cat
        asciiquarium # ascii aquarium

        #  Fine-tune packages by applying overrides, for example
        # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; }) # Nerd Fonts with a limited number of fonts
        # simple shell scripts
        # (writeShellScriptBin "my-hello" ''
        #   echo "Hello, ${config.home.username}!"
        # '')

        discordo
        jellyfin-tui
      ]
      ++ lib.optionals stdenv.isLinux [
        # atopile     # circuit diagrams as code
        # ventoy-full # flash multiple isos to usb
        # super-slicer # 3D printing
        freecad
        woeusb-ng     # flash bootable windows iso

        # ============= 🧑‍💻🐞✨‍ ================
        ugm           # user group management
        isd           # systemd units
        dysk          # see mounted
        kmon          # kernel monitor
        lazyssh       # ssh
        termshark     # wireshark-like TUI
        systeroid     # powerful sysctl alternative
        netscanner
        lazyjournal   # journal logs
        systemctl-tui # systemctl logs

        virt-viewer
        smartmontools
        # qmk
        # qmk_hid
        # qmk-udev-rules

        # ============== 🤪 =================
        hollywood
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
        gparted

        impala        # wifi mgmt tui
        bluetui

        blink
        crates-tui
        arduino-ide
        webcord-vencord

        penpot-desktop
      ]
      ++ lib.optionals stdenv.isDarwin [
        utm          # virtual machines on macos
        ttyd         # ttyd -aWB -t fontSize=16 -t fontFamily="'JetBrainsMono Nerd Font'" -t enableSixel=true -t enableZmodem=true -t enableTrzsz=true zsh
        ninja
        ccache
        dfu-util
      ];

    file = {
      # Building this configuration will create a copy of 'dotfiles/screenrc' in
      # the Nix store. Activating the configuration will then make '~/.screenrc' a
      # symlink to the Nix store copy.
      # .screenrc".source = dotfiles/screenrc;
      ".config/surfingkeys/.surfingkeys.js" = {
        enable = true;
        source = ./programs/surfingkeys/index.js;
      };

      "/Library/Application Support/kanata/kanata.kbd" = {
        enable = pkgs.stdenv.isDarwin;
        source = ../darwin/kanata.kbd;
      };
    };
  };
}

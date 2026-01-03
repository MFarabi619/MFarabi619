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
        # ============= 🤖 ==================
        tree
        pixi # multi-language package manager
        pnpm
        cmake # vterm compilation and more
        duckdb
        gnumake
        stylelint
        platformio
        # vi-mongo        # mongodb tui
        # fritzing
        # arduino-cli
        kubernetes-helm
        # arduino-language-server
        # =============
        # kicad
        # logseq
        vips # dired image previews
        openscad
        mediainfo
        openscad-lsp
        imagemagick # for image-dired
        poppler-utils # dired pdf previews
        epub-thumbnailer # dired epub previews
        ffmpegthumbnailer
        # =============
        sqlite # :tools lookup & :lang org +roam
        gnuplot
        shellcheck # shell script formatting
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support
        # ============= 🧑‍💻🐞✨‍ ================
        # tsui           # tailscale tui, not on nixpkgs yet | curl -fsSL https://neuralink.com/tsui/install.sh | bash
        pik # local port tui
        tgpt
        nmap
        lazyssh # ssh tui
        gpg-tui
        termscp
        tcpdump
        cointop # crypto price feed
        caligula # disk imaging
        wiki-tui
        keymapviz # visualize keyboard layout in ascii
        bandwhich
        cargo-seek
        # leetcode-tui
        # keymap-drawer # visualize keyboard layout
        nvtopPackages.full # btop for gpu

        gama-tui # github actions runners
        codeberg-cli

        exercism
        presenterm
        wireshark-cli
        # ============= ‍❄🕸 ================
        nil # nix formatter
        # omnix
        devenv
        cachix
        nix-du # store visualizer
        # nix-ld      # run unpatched dynamic binaries
        nix-btm # nix process monitor
        nix-top # nix process visualizer
        nix-web # web gui
        nix-info
        # mcp-nixos # mcp server for NixOS
        nix-health # health check
        nix-inspect # flake explorer tui
        nix-weather # check binary cache availability
        # ============== 🤪 =================
        genact # nonsence activity generator
        smassh # TUI monkeytype
        cowsay # ascii cow
        lolcat # rainbow text output
        figlet # fancy ascii text output
        cmatrix # matrix animation
        nyancat # rainbow flying cat
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
        # ============== 🤪 =================
        hollywood # movie hacker screen animation

        # atopile     # circuit diagrams as code
        # ventoy-full # flash multiple isos to usb
        # super-slicer # 3D printing
        freecad
        woeusb-ng # flash bootable windows iso
        virt-viewer
        smartmontools

        # ============= 🧑‍💻🐞✨‍ ================
        ugm # user group management
        isd # systemd units
        dysk # see mounted
        kmon # kernel monitor
        termshark # wireshark-like TUI
        systeroid # powerful sysctl alternative
        netscanner
        lazyjournal # journal logs
        # lazyhetzner
        systemctl-tui # systemctl logs

        # qmk
        # qmk_hid
        # qmk-udev-rules
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
        blink
        impala # wifi mgmt tui
        gparted
        bluetui
        crates-tui
        # stm32cubemx
        # arduino-ide
        # penpot-desktop
        # webcord-vencord
      ]
      ++ lib.optionals stdenv.isDarwin [
        utm # virtual machines on macos
        llvm # compiler toolchain
        ttyd # ttyd -aWB -t fontSize=16 -t fontFamily="'JetBrainsMono Nerd Font'" -t enableSixel=true -t enableZmodem=true -t enableTrzsz=true zsh
        ccache
        avrdude
        dfu-util
        minikube
        dfu-programmer
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

# TODO: check these out

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
# bagels
# moneyterm
# ticker
# mqtttui
# taproom
# tuistash
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

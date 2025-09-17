# uvx parllama
# uvx netshow
# uvx exosphere
# cargo-selector
# systemd-manager mtui
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
# arduino-cli-interactive
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
        pnpm
        gnutls # for TLS connectivity
        # =============
        # kicad
        # logseq
        freecad
        openscad
        openscad-lsp
        # =============
        vips # dired image previews
        imagemagick # for image-dired
        poppler-utils # dired pdf previews
        epub-thumbnailer # dired epub previews
        # =============
        tuntox # collab
        sqlite # :tools lookup & :lang org +roam
        ispell # spelling
        gnuplot
        shellcheck # shell script formatting
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support
        penpot-desktop
        # ============= 🧑‍💻🐞✨‍ ================
        # tsui # tailscale tui, not on nixpkgs yet | curl -fsSL https://neuralink.com/tsui/install.sh | bash
        nmap
        tgpt
        dysk # view disk usage
        pik # local port tui
        sshs # ssh tui
        impala # wifi mgmt tui
        gpg-tui
        bluetui
        termscp
        tcpdump
        cointop # crypto price feed
        wiki-tui
        bandwhich
        cargo-seek

        # leetcode-tui

        keymapviz # visualize keyboard layout in ascii
        # keymap-drawer # visualize keyboard layout

        # lazyhetzner
        caligula # disk imaging

        gama-tui
        codeberg-cli

        vi-mongo

        tree
        presenterm

        wireshark-cli

        stylelint
        # ============= ‍❄🕸 ================
        nil # nix formatter
        omnix
        devenv
        cachix
        nix-du # store visualizer
        # nix-ld # run unpatched dynamic binaries
        nix-btm # nix process monitor
        nix-top # nix process visualizer
        nix-web # web gui
        nix-info
        # mcp-nixos # mcp server for NixOS
        nix-health # health check
        nix-inspect # flake explorer tui
        nix-weather # check binary cache availability

        # `man home-configuration.nix`'s pager to work on Ubuntu
        less

        # ============= 🤖 ==================
        # https://github.com/Vaishnav-Sabari-Girish/arduino-cli-interactive?ref=terminaltrove
        cmake # vterm compilation and more
        gnumake
        gparted
        coreutils
        platformio
        arduino-cli
        arduino-language-server

        fritzing

        woeusb-ng # flash bootable windows iso

        # Setup Claude Code using Google Vertex AI Platform
        # https://github.com/juspay/vertex
        # flake.inputs.vertex.packages.${system}.default

        # ============== 🤪 =================
        genact
        cowsay
        lolcat # rainbow text output
        figlet # fancy ascii text output
        cmatrix
        nyancat # rainbow flying cat
        asciiquarium # ascii aquarium

        #  Fine-tune packages by applying overrides, for example
        # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; }) # Nerd Fonts with a limited number of fonts
        # simple shell scripts
        # (writeShellScriptBin "my-hello" ''
        #   echo "Hello, ${config.home.username}!"
        # '')

        discordo
        # nvtopPackages.full
      ]
      ++ lib.optionals stdenv.isLinux [
        # ============= 🧑‍💻🐞✨‍ ================
        ugm # user group management
        isd # systemd units
        dysk # see mounted
        kmon
        termshark # wireshark-like TUI
        systeroid # powerful sysctl alternative
        netscanner
        lazyjournal
        systemctl-tui

        virt-viewer
        smartmontools
        # qmk
        # qmk_hid
        # qmk-udev-rules

        # ============== 🤪 =================
        hollywood
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
        blink
        crates-tui
        arduino-ide
        webcord-vencord
      ]
      ++ lib.optionals stdenv.isDarwin [
        sbarlua
        alt-tab-macos
        sketchybar-app-font
      ];

    file = {
      # Building this configuration will create a copy of 'dotfiles/screenrc' in
      # the Nix store. Activating the configuration will then make '~/.screenrc' a
      # symlink to the Nix store copy.
      # .screenrc".source = dotfiles/screenrc;
      ".config/surfingkeys/.surfingkeys.js" = {
        enable = true;
        source = ./programs/.surfingkeys.js;
      };
    };
  };
}

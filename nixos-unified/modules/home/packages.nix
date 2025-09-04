# uvx parllama
# uvx netshow
# uvx exosphere
# cargo-selector
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
# blink
# calcure
# duf
# gama
# goto
# sshclick
# hostctl
# neoss
# nap
# pinix
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
        crates-tui
        nmap
        tgpt
        dysk # view disk usage
        pik # local port tui
        sshs # ssh tui
        impala # wifi mgmt tui
        wiki-tui
        gpg-tui
        bluetui
        termscp
        tcpdump
        cointop # crypto price feed
        bandwhich

        # lazyhetzner
        caligula # disk imaging

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

        framework-tool

        woeusb-ng # flash bootable windows iso

        # Setup Claude Code using Google Vertex AI Platform
        # https://github.com/juspay/vertex
        # flake.inputs.vertex.packages.${system}.default

        # ============== 🤪 =================
        cowsay
        lolcat # rainbow text output
        figlet # fancy ascii text output
        nyancat # rainbow flying cat
        cmatrix
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
        netscanner
        lazyjournal
        systemctl-tui

        virt-viewer
        smartmontools

        # ============== 🤪 =================
        hollywood
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [
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

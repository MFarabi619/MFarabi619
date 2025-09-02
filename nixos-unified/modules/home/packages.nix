# uvx parllama
# uvx netshow
# uvx exosphere
# crates-tui
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
# dysk
# gama
# hostctl
# neoss
# nap
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
        ast-grep
        tree-sitter
        # clang
        # =============
        # binutils # native-comp needs 'as', provided by this
        gnutls # for TLS connectivity
        nmap
        # =============
        # kicad
        freecad
        openscad
        openscad-lsp
        # =============
        vips # dired image previews
        epub-thumbnailer # dired epub previews
        poppler-utils # dired pdf previews
        imagemagick # for image-dired
        # =============
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support
        gnuplot
        # =============
        tuntox # collab
        # =============
        sqlite # :tools lookup & :lang org +roam
        # =============
        ispell # spelling
        # =============
        shellcheck # shell script formatting
        penpot-desktop
        # =============
        # vimPlugins.nvim-treesitter-parsers.mermaid
        # ============= 🧑‍💻🐞✨‍ ================
        # pnpm
        tgpt
        pik # local port tui
        sshs # ssh tui
        impala # wifi mgmt tui
        wiki-tui
        gpg-tui
        bluetui
        termscp
        bandwhich
        tcpdump
        cointop # crypto price feed

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
        nix-info
        nix-inspect
        nixpkgs-fmt
        nix-health
        nix-weather

        # `man home-configuration.nix`'s pager to work on Ubuntu
        less

        # ============= 🤖 ==================
        # https://github.com/Vaishnav-Sabari-Girish/arduino-cli-interactive?ref=terminaltrove
        cmake # vterm compilation and more
        gnumake
        gparted
        coreutils
        arduino-cli
        arduino-language-server
        platformio

        fritzing

        via
        vial

        framework-tool

        woeusb-ng # flash bootable windows iso

        # Setup Claude Code using Google Vertex AI Platform
        # https://github.com/juspay/vertex
        # flake.inputs.vertex.packages.${system}.default

        # ============== 🤪 =================
        asciiquarium # ascii aquarium
        cowsay
        cmatrix
        figlet # fancy ascii text output
        nyancat # rainbow flying cat
        lolcat # rainbow text output

        #  Fine-tune packages by applying overrides, for example
        # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; }) # Nerd Fonts with a limited number of fonts
        # simple shell scripts
        # (writeShellScriptBin "my-hello" ''
        #   echo "Hello, ${config.home.username}!"
        # '')

        discordo
      ]
      ++ lib.optionals stdenv.isLinux [
        arduino-ide
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
        sketchybar-app-font
        sbarlua
        alt-tab-macos
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

{
  lib,
  pkgs,
  config,
  ...
}:
{
  home = {
    packages =
      with pkgs;
      [
        loco
        trunk
        libyaml
        binaryen
        rustywind
        dioxus-cli
        sea-orm-cli
        tailwindcss_4
        wasm-bindgen-cli
        rubyPackages_3_4.rails
      ]
      ++ [
        tio
        SDL2 # for embedded TUI simulator
        espup
        esptool
        esphome
        espflash
        esp-generate
        mcumgr-client
        cargo-embassy
        cargo-generate
        cargo-binstall
        renode-dts2repl
        kconfig-frontends
        home-assistant-cli

        (probe-rs-tools.overrideAttrs (old: {
          cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "remote" ];
        }))

        (python314.withPackages (
          package:
          with package;
          [
            dtc
            west
            tqdm
            cbor
            cbor2
            click
            patool
            jinja2
            anytree
            tkinter
            intelhex
            requests
            pyelftools
            jsonschema
            cryptography
          ]
          ++ [
            pyusb
            pyserial
          ]
          ++ [
            semver
            pygments
            kconfiglib
          ]
          ++ [
            # NOTE: for west twister
            psutil
            pytest
            natsort
            tabulate # for --device-testing
            junitparser
          ]
        ))
      ]
      ++ [
        flock
      ]
      ++ [
        lighttpd
        radicle-tui
        radicle-httpd
        radicle-desktop
        radicle-explorer
        # TODO: are these already provided by services.radicle or programs.radicle?
        # radicle-job
        # radicle-ci-broker
        # radicle-native-ci
      ]
      ++ [
        sqlite # :tools lookup & :lang org +roam
        grafana
        talosctl
        bore-cli
        grafanactl
        supabase-cli
        mcp-grafana # https://github.com/grafana/mcp-grafana
      ]
      ++ [
        llvm
        lldb
        ninja
        cmake
        ccache
        gnumake
        ldproxy
        openocd
        # avrdude
        dfu-util
        dfu-programmer
      ]
      ++ [
        socat
        godot
        delve
        bashdb
        dts-lsp
        asm-lsp
        crates-lsp
        postgres-language-server
        # ============= 🤖 ==================
        tree
        pixi # multi-language package manager
        pnpm
        duckdb
        stylelint
        # vi-mongo  # mongodb tui
        # fritzing
        kubernetes-helm
        # =============
        ispell
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
        gnuplot
        shellcheck # shell script formatting
        octaveFull # gnu octave
        mermaid-cli # mermaid diagram support

        # ============= 🧑‍💻🐞✨‍ ================
        # tsui           # tailscale tui, not on nixpkgs yet | curl -fsSL https://neuralink.com/tsui/install.sh | bash
        pik # local port tui
        sops
        tgpt
        nmap
        lazyssh # ssh tui
        gpg-tui
        # termscp
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

        # gama-tui # github actions runners
        # codeberg-cli

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
        # mcp-nixos
        nix-health # health check
        nix-inspect # flake explorer tui
        nix-weather # check binary cache availability

        # ============== 🤪 =================
        genact # nonsense activity generator
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
      ]
      ++ [
        discordo
        jellyfin-tui
      ]
      ++ lib.optionals stdenv.isDarwin [
        utm # virtual machines on macos
        ttyd # ttyd -aWB -t fontSize=16 -t fontFamily="'JetBrainsMono Nerd Font'" -t enableSixel=true -t enableZmodem=true -t enableTrzsz=true zsh
        # quickemu # broken as of Sun May 10 18:29:41 EDT 2026. error: Cannot build '/nix/store/3swsq60jxg8qdrpv7kjm19xah38r64d4-samba-4.23.5.drv'.
        minikube
        binsider
        vscode-extensions.llvm-vs-code-extensions.lldb-dap
      ]
      ++ lib.optionals stdenv.isLinux (
        [
          # ============== 🤪 ================
          hollywood # movie hacker screen animation

          # atopile     # circuit diagrams as code
          # ventoy-full # flash multiple isos to usb
          # super-slicer # 3D printing
          woeusb-ng # flash bootable windows iso
          virt-viewer
          smartmontools
        ]
        ++ [
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
        ++ [
          atk
          glib
          file
          cairo
          pango
          xdotool
          openssl
          librsvg
          pkg-config
          webkitgtk_4_1
          libappindicator-gtk3
        ]
        ++ lib.optionals config.wayland.windowManager.hyprland.enable [
          wl-screenrec
          wl-clipboard
        ]
        ++ lib.optionals stdenv.isx86_64 [
          # x86_64-linux only — these pull fltk-1.3.11 via gmsh, which currently
          # fails to build on aarch64-linux in this nixpkgs revision.
          # Drop gate once aarch64 fltk works.
          freecad
        ]
        ++ lib.optionals stdenv.isx86_64 [
          blink
          impala # wifi mgmt tui
          gparted
          bluetui
          crates-tui
          # stm32cubemx
          # penpot-desktop
          # webcord-vencord
        ]
      );

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

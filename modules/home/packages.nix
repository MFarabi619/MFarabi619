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
        vips
        godot
        ispell
        gnuplot
        graphviz
        plantuml
        libsixel
        mediainfo
        mermaid-cli
        ghostscript
        imagemagick
        poppler-utils
        epub-thumbnailer
        ffmpegthumbnailer
      ]
      ++ [
        # kicad
        fritzing
        octaveFull
        openscad
        openscad-lsp
      ]
      ++ [
        tuntox
        gnutls
        eask-cli
      ]
      ++ [
        duckdb
        sqlite
        supabase-cli
      ]
      ++ [
        pnpm
        loco
        trunk
        libyaml
        binaryen
        rustywind
        dioxus-cli
        sea-orm-cli
        virt-viewer
        attic-client
        tailwindcss_4
        wasm-bindgen-cli
        rubyPackages_3_4.rails
      ]
      ++ [
        llvm
        lldb
        flock
        ninja
        cmake
        ccache
        gnumake
        ldproxy
        openocd
        dfu-util
        dfu-programmer
        (probe-rs-tools.overrideAttrs (old: {
          cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "remote" ];
        }))
      ]
      ++ [
        esptool
        esphome
        espflash
        cargo-seek
        esp-generate
        cargo-embassy
        cargo-generate
        cargo-binstall
        renode-dts2repl
        kconfig-frontends
        home-assistant-cli
        (python314.withPackages (
          package:
          with package;
          [
            dtc
            west
            tqdm
            rich
            cbor
            cbor2
            click
            plotly
            patool
            jinja2
            anytree
            tkinter
            intelhex
            requests
            colorama
            pyelftools
            jsonschema
            cryptography
          ]
          ++ [
            pyocd
            pyusb
            zeroconf
            pyserial
            pylink-square
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
        lighttpd
        radicle-tui
        # radicle-job
        radicle-httpd
        radicle-desktop
        radicle-explorer
      ]
      ++ [
        grafana
        grafanactl
        mcp-grafana
      ]
      ++ [
        talosctl
        minikube
        process-compose
        kubernetes-helm
      ]
      ++ [
        socat
        bore-cli
        smartmontools
      ]
      ++ [
        shfmt
        bashdb
        shellcheck
        bash-language-server
        (bats.withLibraries (
          batsPackages: with batsPackages; [
            bats-file
            bats-assert
            bats-support
          ]
        ))
      ]
      ++ [
        nil
        nixfmt
        statix
      ]
      ++ [
        ccls
        delve
        asmfmt
        asm-lsp
        dts-lsp
        crates-lsp
        cmake-language-server
      ]
      ++ [ ruby-lsp ]
      ++ [
        buf # protobuf lsp
        protobuf
        protoc-gen-go
        protoc-gen-go-grpc
      ]
      ++ [
        # ===== 🦫 GO 🦫 ======
        gore
        gotests
        gomodifytags
        gocode-gomod
        golangci-lint
      ]
      ++ [
        taplo
        jq-lsp
        lemminx # xml lsp
        stylelint
        astro-language-server
        postgres-language-server
        vscode-json-languageserver
        graphql-language-service-cli
        # semgrep
        # eslint
        # emmet-ls
        # proselint
        # markdownlint-cli
        # mdx-language-server
        # yaml-language-server
        # dockerfile-language-server
        # vscode-langservers-extracted
        # ============= 🤖 ==================
        tree
        # vi-mongo # mongodb tui
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
        # gama-tui # github actions runners
        # leetcode-tui
        # keymap-drawer # visualize keyboard layout
        # codeberg-cli
      ]
      ++ lib.optionals (!config.targets.genericLinux.enable) [
        nvtopPackages.full # btop for gpu; genericLinux hosts set their own variant per-host
      ]
      ++ lib.optionals (stdenv.isLinux && stdenv.isx86_64) [ ]
      ++ [
        exercism
        presenterm
        wireshark-cli
      ]
      ++ [
        # ============= ‍❄🕸 ================
        omnix
        nix-du # store visualizer
        devenv
        vulnix
        cachix
        deadnix
        # nix-ld      # run unpatched dynamic binaries
        nix-btm # nix process monitor
        nix-top # nix process visualizer
        nix-web # web gui
        nix-inspect # flake explorer tui
        nix-weather # check binary cache availability
      ]
      ++ [
        # ============== 🤪 =================
        genact # nonsense activity generator
        smassh # TUI monkeytype
        cowsay
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
        binsider
        vscode-extensions.llvm-vs-code-extensions.lldb-dap
      ]
      ++ lib.optionals stdenv.isLinux (
        [
          pixi
        ]
        ++ [
          espup
          # ============== 🤪 ================
          hollywood # movie hacker screen animation

          # atopile     # circuit diagrams as code
          # ventoy-full # flash multiple isos to usb
          # super-slicer # 3D printing
          woeusb-ng # flash bootable windows iso
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

{
  lib,
  pkgs,
  flake,
  config,
  ...
}:
{
  imports = [ flake.inputs.nix-doom-emacs-unstraightened.homeModule ];

  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    experimentalFetchTree = config.targets.genericLinux.enable;

    extraPackages =
      epkgs:
      let
        treesitWithAllExceptQuint = epkgs.treesit-grammars.with-grammars (
          grammars: builtins.attrValues (builtins.removeAttrs grammars [ "tree-sitter-quint" ])
        );
      in
      with epkgs;
      [ sops ]
      ++ [
        eask
        easky
        eask-mode
        eldoc-eask
        company-eask
        flymake-eask
        flycheck-eask
      ]
      ++ [
        vui
        # uniline
        verdict
        dag-draw
        websocket
      ]
      ++ [
        ccls
        disaster
        abc-mode
        kdl-mode
        bats-mode
        scad-mode
        sqlup-mode
        eldoc-cmake
        kconfig-ref
        kconfig-mode
        mermaid-mode # github.com/abrochard/mermaid-mode
        colorful-mode
        devicetree-ts-mode
        treesitWithAllExceptQuint
        # treesit-grammars.with-all-grammars
      ]
      ++ [
        nov
        mu4e
        mu4e-views
        mu4e-column-faces
        mu4e-marker-icons
      ]
      ++ [
        osm
        empv
        verb
        # gptel
        circe
        ghostel
        buttercup
        magit-todos
        magit-delta
        claude-code
      ]
      ++ [
        devdocs
        devdocs-browser
        compiler-explorer
      ]
      ++ [
        multi-vterm
        compile-multi
        fancy-compilation
        compile-multi-embark
        consult-compile-multi
      ]
      ++ [
        org-anki
        ob-duckdb
        ob-mermaid
        org-roam-ui
        org-nix-shell
        org-web-tools
        org-auto-tangle
        org-super-agenda
        org-tag-beautify
        org-link-beautify
        org-table-highlight
      ]
      ++ [
        wttrin
        shrface
        keycast
        leetcode
        exercism
        nix-update
        nixos-options
        all-the-icons
      ]
      ++ [
        hass
        parrot
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        # catppuccin-theme
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ consult-spotlight ];

    extraBinPackages =
      with pkgs;
      [ nixfmt ]
      ++ [
        buf # protobuf lsp
        protobuf
        protoc-gen-go
        protoc-gen-go-grpc
      ]
      ++ [
        jq-lsp
        graphql-language-service-cli
      ]
      # ===== 🛠 ASSEMBLY 🛠 ====
      ++ [ asmfmt ]
      ++ [
        # ===== 🦫 GO 🦫 ======
        gore
        gotests
        gomodifytags
        gocode-gomod
        golangci-lint
      ]
      # ==== 🚂 RUBY 🚂 ===
      ++ [ ruby-lsp ]
      ++ [
        graphviz
        plantuml
      ]
      ++ [
        fd
        git
        tuntox # collab
        gnutls # :app irc
        ripgrep
        # semgrep
      ]
      ++ [
        taplo
        # eslint
        # emmet-ls
        # proselint
        # markdownlint-cli
        # mdx-language-server
        # yaml-language-server
        # dockerfile-language-server
        # vscode-langservers-extracted
      ];
  };
}

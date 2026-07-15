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
      lib.optionals pkgs.stdenv.isDarwin [ consult-spotlight ]
      ++ [ sops ]
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
        buttercup
      ]
      ++ [
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
        astro-ts-mode
        colorful-mode
        devicetree-ts-mode
        treesitWithAllExceptQuint
        # treesit-grammars.with-all-grammars
      ]
      ++ [
        nix-update
        nixos-options
      ]
      ++ [
        nov
        mu4e
        shrface
        mu4e-views
        mu4e-column-faces
        mu4e-marker-icons
      ]
      ++ [
        osm
        verb
        empv
        circe
        # gptel
        # ghostel
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
        hass
        parrot
        wttrin
        pacmacs
        keycast
        leetcode
        exercism
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        all-the-icons
        # catppuccin-theme
      ];
  };
}

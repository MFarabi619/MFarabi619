{
  pkgs,
  ...
}:
{
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    # provideEmacs = false;
    # experimentalFetchTree = true;

    extraPackages = epkgs:
      let
        treesitWithAllExceptRazor =
          epkgs.treesit-grammars.with-grammars (grammars:
            builtins.attrValues (builtins.removeAttrs grammars [
              "tree-sitter-razor"
              "tree-sitter-razor-grammar"
            ])
          );
      in
      with epkgs; [
        pg
        nov
        mu4e
        verb
        gptel            # ai
        vterm            # terminal emulation
        circe
        corfu
        corfu-terminal
        nerd-icons-corfu

        wttrin
        devdocs
        devdocs-browser
        shrface
        keycast
        kdl-mode
        leetcode
        exercism
        nix-update
        nix-ts-mode
        all-the-icons
        compiler-explorer

        lsp-tailwindcss
        treesitWithAllExceptRazor
        # ================
        abc-mode
        scad-mode
        ob-mermaid
        mermaid-mode     # github.com/abrochard/mermaid-mode
        org-table-highlight
        # ================
        pdf-tools
        org-roam-ui
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        org-super-agenda
        # ================
        # jira
        # obsidian
        # platformio-mode
        # catppuccin-theme
      ];

    extraBinPackages = with pkgs; [
      fd
      git
      ispell
      duckdb
      # pandoc
      tuntox # collab
      semgrep
      ripgrep
      graphviz
      plantuml
      coreutils
      rustywind
    ];
  };

  services.emacs = {
    enable = true;
    defaultEditor = false;
    socketActivation.enable = true;

    # extraOptions = [
    #   "TERM=xterm-kitty"
    # ];

    client = {
      enable = true;
      # arguments = [
      #   "--tty"
      # ];
    };
  };
}

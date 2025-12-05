{
  pkgs,
  ...
}:
{
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    extraPackages =
      epkgs: with epkgs; [
        pg
        nov
        mu4e
        # jira
        verb
        gptel
        vterm
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

        lsp-tailwindcss
        treesit-grammars.with-all-grammars
        # ================
        abc-mode
        scad-mode
        ob-mermaid # org babel mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
        org-table-highlight
        # ================
        obsidian
        pdf-tools
        org-roam-ui
        # platformio-mode
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        org-super-agenda
        # ================
        # catppuccin-theme
      ];

    # provideEmacs = false;
    extraBinPackages = with pkgs; [
      fd
      git
      ispell
      duckdb
      tuntox # collab
      semgrep
      ripgrep
      plantuml
      coreutils
      rustywind
    ];

    # experimentalFetchTree = true;
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

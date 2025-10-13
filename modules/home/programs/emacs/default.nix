{
  pkgs,
  ...
}:
{
  home.shellAliases.enw = "emacsclient -nw";
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
        nix-update
        nix-ts-mode
        all-the-icons
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
        # ================
        # arduino-mode
        # platformio-mode
        # company-arduino
        # arduino-cli-mode
        # ================
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        org-super-agenda
        # ================
        catppuccin-theme
      ];

    # provideEmacs = false;
    # extraBinPackages = with pkgs; [fd git ripgrep];
    experimentalFetchTree = true;
  };

  services.emacs = {
    enable = true;
    client = {
      enable = true;
      # arguments = [];
    };
    defaultEditor = false;
    # extraOptions = [ "-nw" ];
    socketActivation.enable = true;
  };
}

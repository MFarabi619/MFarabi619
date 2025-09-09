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
        jira
        verb
        gptel
        vterm
        circe
        wttrin
        devdocs
        keycast
        kdl-mode
        leetcode
        treesit-grammars.with-all-grammars
        # ================
        abc-mode
        scad-mode
        ob-mermaid # org babel mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
        # ================
        obsidian
        pdf-tools
        org-roam-ui
        # ================
        arduino-mode
        company-arduino
        arduino-cli-mode
        # ================
        pacmacs
        key-quiz
        nyan-mode
        fireplace
        fretboard
        speed-type
        chordpro-mode
        org-super-agenda
      ];

    # provideEmacs = false;
        # experimentalFetchTree = true;
    # extraBinPackages = with pkgs; [fd git ripgrep];
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

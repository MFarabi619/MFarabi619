{
  home.shellAliases.enw = "emacsclient -nw";
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    extraPackages =
      epkgs: with epkgs; [
        mu4e
        jira
        ast-grep
        editorconfig
        xclip
        wttrin
        # ================
        shfmt
        nixfmt
        # ================
        rustic
        # ================
        lua-mode
        lsp-mode
        lsp-java
        lsp-latex
        rust-mode
        lsp-scheme
        lsp-docker
        lsp-pyright
        lsp-haskell
        lsp-treemacs
        lsp-tailwindcss
        # ================
        ob-mermaid # org babel mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
        # ================
        lua
        # ================
        npm
        typescript-mode
        jtsx
        vue3-mode
        # ================
        yaml
        # ================
        pdf-tools
        # ================
        arduino-mode
        company-arduino
        arduino-cli-mode
        tree-sitter-langs
      ];
    # provideEmacs = false;
  };

  services.emacs = {
    enable = true;
    socketActivation.enable = true;
    client.enable = true;
    defaultEditor = false;
    # extraOptions = [
    #   "-nw"
    # ];
  };
}

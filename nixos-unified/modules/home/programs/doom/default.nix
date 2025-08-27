{
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    extraPackages =
      epkgs: with epkgs; [
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
        rust-mode
        lsp-mode
        lua-mode
        lsp-java
        lsp-docker
        lsp-latex
        lsp-pyright
        lsp-tailwindcss
        lsp-treemacs
        lsp-haskell
        lsp-scheme
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

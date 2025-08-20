{
  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    extraPackages =
      epkgs: with epkgs; [
        editorconfig
        xclip
        wttrin
        # ================
        shfmt
        nixfmt
        # ================
        rustic
        # ================
        lsp-java
        lsp-docker
        lsp-latex
        lsp-pyright
        lsp-tailwindcss
        lsp-treemacs
        lsp-haskell
        # ================
        ob-mermaid # org babel mermaid
        mermaid-mode # github.com/abrochard/mermaid-mode
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
      ];
    # provideEmacs = false;
  };

  services.emacs = {
    enable = true;
    socketActivation.enable = true;
    client.enable = true;
    # extraOptions = [
    #   "-nw"
    # ];
  };
}

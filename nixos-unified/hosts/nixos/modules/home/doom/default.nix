{
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-doom-emacs-unstraightened.homeModule
  ];

  programs = {
    doom-emacs = {
      enable = true;
      doomDir = ./.;
      extraPackages = epkgs: [
        epkgs.pdf-tools
        epkgs.editorconfig
        epkgs.shfmt
        epkgs.nixfmt
        epkgs.npm
        epkgs.rustic
        epkgs.lsp-java
        epkgs.lsp-docker
        epkgs.lsp-latex
        epkgs.lsp-pyright
        epkgs.lsp-tailwindcss
        epkgs.lsp-treemacs
        epkgs.lsp-haskell
        epkgs.typescript-mode
        epkgs.jtsx
        epkgs.yaml
        epkgs.xclip
        epkgs.wttrin
        epkgs.vue3-mode
      ];
      # provideEmacs = false;
    };
  };

  services = {
    emacs = {
      enable = true;
      socketActivation.enable = true;
      client.enable = true;
    };
  };
}

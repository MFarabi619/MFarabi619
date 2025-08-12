{
  flake,
  pkgs,
  inputs,
  ...
}:
{

  imports = [
    flake.inputs.nix-doom-emacs-unstraightened.homeModule
  ];

  programs.doom-emacs = {
    enable = true;
    doomDir = ./.;
    extraPackages =
      epkgs: with epkgs; [
        pdf-tools
        editorconfig
        shfmt
        nixfmt
        npm
        rustic
        lsp-java
        lsp-docker
        lsp-latex
        lsp-pyright
        lsp-tailwindcss
        lsp-treemacs
        lsp-haskell
        typescript-mode
        jtsx
        yaml
        xclip
        wttrin
        vue3-mode
      ];
    # provideEmacs = false;
  };

  services.emacs = {
    enable = true;
    socketActivation.enable = true;
    client.enable = true;
    extraOptions = [
      "-nw"
    ];
  };
}

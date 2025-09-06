{ inputs, pkgs, ... }:

{
  home-manager = {
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;

    config = {
      home = {
        stateVersion = "24.05";
        packages = with pkgs; [
          noto-fonts

          tree

          cachix
          nil
          nix-info
          nix-inspect

          termscp
        ];
      };

      imports = [
        inputs.stylix.homeModules.stylix
        # inputs.nix-doom-emacs-unstraightened.homeModule
        # ../../../modules/home/programs/emacs
        # ../../../modules/home/home.nix
        ../../../modules/home/services
        ../../../modules/home/editorconfig.nix
        ../../../modules/home/fonts.nix
        ../../../modules/home/stylix.nix
        ../../../modules/home/manual.nix
        ../../../modules/home/programs/bash.nix
        ../../../modules/home/programs/bat.nix
        ../../../modules/home/programs/btop.nix
        ../../../modules/home/programs/direnv.nix
        ../../../modules/home/programs/eza.nix
        ../../../modules/home/programs/fastfetch
        ../../../modules/home/programs/fd.nix
        ../../../modules/home/programs/fzf.nix
        ../../../modules/home/programs/gcc.nix
        ../../../modules/home/programs/gh.nix
        ../../../modules/home/programs/git.nix
        ../../../modules/home/programs/go.nix
        ../../../modules/home/programs/gpg.nix
        ../../../modules/home/programs/grep.nix
        ../../../modules/home/programs/home-manager.nix
        ../../../modules/home/programs/jq.nix
        ../../../modules/home/programs/jqp.nix
        ../../../modules/home/programs/lazygit.nix
        ../../../modules/home/programs/lazysql.nix
        ../../../modules/home/programs/less.nix
        ../../../modules/home/programs/mu.nix
        ../../../modules/home/programs/neovim
        ../../../modules/home/programs/nh.nix
        ../../../modules/home/programs/nix-index.nix
        ../../../modules/home/programs/nix-search-tv.nix
        ../../../modules/home/programs/pandoc.nix
        ../../../modules/home/programs/ripgrep.nix
        ../../../modules/home/programs/television.nix
        ../../../modules/home/programs/tex-fmt.nix
        ../../../modules/home/programs/texlive.nix
        ../../../modules/home/programs/tmux.nix
        ../../../modules/home/programs/uv.nix
        ../../../modules/home/programs/yazi.nix
        ../../../modules/home/programs/zellij.nix
        ../../../modules/home/programs/zoxide.nix
        ../../../modules/home/programs/zsh
      ];
    };
  };
}

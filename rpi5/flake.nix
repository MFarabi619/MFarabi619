{
  description = "Raspberry Pi 5 (Raspberry Pi OS or Ubuntu) + Nix + Home Manager configuration.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";

    lazyvim.url = "github:pfassina/lazyvim-nix";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      stylix,
      home-manager,
      nix-doom-emacs-unstraightened,
      ...
    }@inputs:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      homeConfigurations."mfarabi" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          inputs.stylix.homeModules.stylix
          inputs.lazyvim.homeManagerModules.default
          inputs.nix-doom-emacs-unstraightened.homeModule

          ({
            targets.genericLinux.enable = true;

            home = {
              username = "mfarabi";
              stateVersion = "25.05";
              homeDirectory = "/home/mfarabi";
            };

            imports = [
              ../modules/home/programs/emacs
              ../modules/home/programs/neovim

              ../modules/home/home.nix
              ../modules/home/services
              ../modules/home/fonts.nix
              ../modules/home/stylix.nix
              ../modules/home/manual.nix
              ../modules/home/editorconfig.nix

              ../modules/home/programs/bat.nix
              ../modules/home/programs/btop.nix
              ../modules/home/programs/command-not-found.nix
              ../modules/home/programs/direnv.nix
              ../modules/home/programs/eza.nix
              ../modules/home/programs/fastfetch
              ../modules/home/programs/fd.nix
              ../modules/home/programs/fzf.nix
              ../modules/home/programs/gcc.nix
              ../modules/home/programs/gh.nix
              ../modules/home/programs/git.nix
              ../modules/home/programs/go.nix
              ../modules/home/programs/gpg.nix
              ../modules/home/programs/grep.nix
              ../modules/home/programs/home-manager.nix
              ../modules/home/programs/info.nix
              ../modules/home/programs/jq.nix
              ../modules/home/programs/jqp.nix
              ../modules/home/programs/kitty
              ../modules/home/programs/k9s.nix
              ../modules/home/programs/kubecolor.nix
              ../modules/home/programs/lazydocker.nix
              ../modules/home/programs/lazygit.nix
              ../modules/home/programs/lazysql.nix
              ../modules/home/programs/less.nix
              ../modules/home/programs/man.nix
              ../modules/home/programs/neovim
              ../modules/home/programs/nh.nix
              ../modules/home/programs/nix-index.nix
              ../modules/home/programs/nix-search-tv.nix
              ../modules/home/programs/openstackclient.nix
              ../modules/home/programs/ripgrep.nix
              ../modules/home/programs/ripgrep-all.nix
              ../modules/home/programs/ssh.nix
              ../modules/home/programs/sftpman.nix
              ../modules/home/programs/television.nix
              ../modules/home/programs/tiny.nix
              ../modules/home/programs/uv.nix
              ../modules/home/programs/vim.nix
              ../modules/home/programs/vivaldi
              ../modules/home/programs/vscode.nix
              ../modules/home/programs/yazi.nix
              ../modules/home/programs/zed.nix
              ../modules/home/programs/zellij.nix
              ../modules/home/programs/zoxide.nix
              ../modules/home/programs/zsh
            ];
          })
        ];
      };
    };
}

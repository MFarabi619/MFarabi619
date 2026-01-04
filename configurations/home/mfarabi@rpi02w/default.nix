{
  pkgs,
  flake,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  programs.docker-cli.enable = true;
  nixpkgs.config.allowUnfree = true;
  targets.genericLinux.enable = true;

  home = {
    stateVersion = "25.05";

    packages = with pkgs; [
      ttyd
      nix-ld
    ];
  };

  imports =
    with self.homeModules;
    [
      me
      home
      fonts
      stylix
      manual
      editorconfig
    ]
    ++ map (p: programs + "/${p}") [
      "neovim"
      "zsh"

      "bat.nix"
      "btop.nix"
      "bun.nix"
      "direnv.nix"
      "eza.nix"
      "fastfetch"
      "fd.nix"
      "fzf.nix"
      "gcc.nix"
      "gh.nix"
      "git.nix"
      "go.nix"
      "gpg.nix"
      "grep.nix"
      "home-manager.nix"
      "info.nix"
      "jq.nix"
      "jqp.nix"
      "lazydocker.nix"
      "lazygit.nix"
      "lazysql.nix"
      "less.nix"
      "man.nix"
      "nh.nix"
      "npm.nix"
      "nix-index.nix"
      "nix-search-tv.nix"
      "ripgrep.nix"
      "ripgrep-all.nix"
      "ssh.nix"
      "sftpman.nix"
      "television.nix"
      "tmux.nix"
      "uv.nix"
      "vim.nix"
      "yazi.nix"
      "zellij.nix"
      "zoxide.nix"
    ];
}

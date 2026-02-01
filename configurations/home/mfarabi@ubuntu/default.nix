{
  pkgs,
  flake,
  config,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  programs.docker-cli.enable = true;

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      flake.inputs.nixGL.overlay
    ];
  };

  targets.genericLinux = {
    enable = true;
    nixGL.packages = flake.inputs.nixGL.packages;
    # nix profile add github:guibou/nixGL --impure
  };

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
      xdg
      home
      fonts
      stylix
      manual
      editorconfig
    ]
    ++ map (f: services + "/${f}") [
      "ollama.nix"
      "gpg-agent.nix"
      "ssh-agent.nix"
      "home-manager.nix"
    ]
    ++ map (p: programs + "/${p}") [
      "hyprland"
      "emacs"
      "neovim"
      "zsh"
      "kitty"

      "bat.nix"
      "btop.nix"
      "bun.nix"
      "command-not-found.nix"
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
      "kitty"
      "k9s.nix"
      "kubecolor.nix"
      "lazydocker.nix"
      "lazygit.nix"
      "lazysql.nix"
      "less.nix"
      "man.nix"
      "nh.nix"
      "npm.nix"
      "nix-index.nix"
      "nix-search-tv.nix"
      "openstackclient.nix"
      "ripgrep.nix"
      "ripgrep-all.nix"
      "ruff.nix"
      "ssh.nix"
      "sftpman.nix"
      "sqls.nix"
      "television.nix"
      "tmux.nix"
      "uv.nix"
      "vim.nix"
      "vivaldi"
      "vscode.nix"
      "yazi.nix"
      "zed.nix"
      "zellij.nix"
      "zoxide.nix"
    ];
}

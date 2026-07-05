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
  xdg.configFile."nix/nix.conf".text = "lazy-trees = false\n";
  targets.genericLinux.enable = true;

  home = {
    stateVersion = "26.05";

    packages = with pkgs; [
      ttyd
      nix-ld
      nvtopPackages.v3d
    ];
  };

  imports =
    with self.homeModules;
    [
      me
      home
      stylix
      manual
      accounts
      packages
      editorconfig
    ]
    ++ map (f: services + "/${f}") [
      "gpg-agent.nix"
      "ssh-agent.nix"
      "home-manager.nix"
    ]
    ++ map (p: programs + "/${p}") [
      "zsh"
      "kitty"
      "emacs"
      "neovim"
      "fastfetch"

      "aria2.nix"
      "aria2p.nix"
      "bat.nix"
      "btop.nix"
      "bun.nix"
      "command-not-found.nix"
      "direnv.nix"
      "delta.nix"
      "eza.nix"
      "fd.nix"
      "fzf.nix"
      "gcc.nix"
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
      "zellij.nix"
      "zoxide.nix"
      "htop.nix"
    ];
}

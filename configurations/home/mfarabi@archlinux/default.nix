{
  lib,
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
  nixpkgs.config.allowUnfree = true;

  targets.genericLinux = {
    enable = true;
    gpu.enable = true;
  };

  home = {
    stateVersion = "25.05";

    packages = with pkgs; [
      yay
      ttyd
      tscli
      arion
      nix-ld
      argocd
      kubectl
      # microk8s
      minikube
      jellyfin
      filebrowser
      # fw-fanctrl
      wl-screenrec
      framework-tool
      argocd-autopilot
      framework-tool-tui
      argocd-vault-plugin
    ];

    file = {
      "hypr-brightness.sh".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/configurations/home/mfarabi@archlinux/hypr-brightness.sh";

      ".config/hypr/animations".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/modules/home/programs/hyprland/hypr/animations";

      ".config/hypr/animations.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/modules/home/programs/hyprland/hypr/animations.conf";

      ".config/hypr/hyprland.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/configurations/home/mfarabi@archlinux/.config/hypr/hyprland.conf";

      ".config/hypr/keybindings.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/configurations/home/mfarabi@archlinux/.config/hypr/keybindings.conf";

      ".config/hypr/monitors.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/configurations/home/mfarabi@archlinux/.config/hypr/monitors.conf";

      ".config/hypr/userprefs.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/configurations/home/mfarabi@archlinux/.config/hypr/userprefs.conf";

      ".config/hypr/windowrules.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/modules/home/programs/hyprland/hypr/windowrules.conf";

      ".config/hypr/devilish_linux_penguin_wide.webp".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/MFarabi619/assets/devilish_linux_penguin_wide.webp";
    };
  };

  imports =
    with self.homeModules;
    [
      me
      home
      fonts
      # stylix
      manual
      editorconfig
    ]
    ++ map (f: services + "/${f}") [
      "mbsync.nix"
      "ollama.nix"
      "gpg-agent.nix"
      "ssh-agent.nix"
      "home-manager.nix"
      "activitywatch.nix"
      "jellyfin-mpv-shim.nix"
    ]
    ++ map (p: programs + "/${p}") [
      "emacs"
      "neovim"
      "zsh"

      "aichat.nix"
      "bat.nix"
      "btop.nix"
      "bun.nix"
      "chromium.nix"
      # "claude-code.nix"
      "command-not-found.nix"
      "direnv.nix"
      "eza.nix"
      # "element-desktop" # disabled due to CVE
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
      # "kitty"
      "k9s.nix"
      "kubecolor.nix"
      "lazydocker.nix"
      "lazygit.nix"
      "lazysql.nix"
      "less.nix"
      "man.nix"
      "mbsync.nix"
      "mu.nix"
      "nh.nix"
      "npm.nix"
      "nix-index.nix"
      "nix-search-tv.nix"
      "openstackclient.nix"
      "obs-studio.nix"
      "opencode.nix"
      "pandoc.nix"
      "ripgrep.nix"
      "ripgrep-all.nix"
      "rtorrent.nix"
      "ruff.nix"
      "ssh.nix"
      "sftpman.nix"
      "sqls.nix"
      "television.nix"
      "tex-fmt.nix"
      "texlive.nix"
      "tiny.nix"
      "tmux.nix"
      "uv.nix"
      "vim.nix"
      # "vivaldi"
      "vscode.nix"
      "yazi.nix"
      "zed.nix"
      "zellij.nix"
      "zoxide.nix"
    ];
}

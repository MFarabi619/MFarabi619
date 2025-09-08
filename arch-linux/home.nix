{
  inputs,
  config,
  pkgs,
  ...
}:

{
  imports = [
    # ../modules/home/accounts.nix
    ../modules/home/home.nix
    ../modules/home/services
    ../modules/home/fonts.nix
    ../modules/home/manual.nix
    ../modules/home/editorconfig.nix

    ../modules/home/programs/aichat.nix
    ../modules/home/programs/emacs
    ../modules/home/programs/bat.nix
    ../modules/home/programs/btop.nix
    ../modules/home/programs/chromium.nix
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
    ../modules/home/programs/jq.nix
    ../modules/home/programs/jqp.nix
    ../modules/home/programs/k9s.nix
    ../modules/home/programs/kubecolor.nix
    ../modules/home/programs/lazydocker.nix
    ../modules/home/programs/lazygit.nix
    ../modules/home/programs/lazysql.nix
    ../modules/home/programs/less.nix
    ../modules/home/programs/man.nix
    ../modules/home/programs/mu.nix
    ../modules/home/programs/neovim
    ../modules/home/programs/nh.nix
    ../modules/home/programs/nix-index.nix
    ../modules/home/programs/nix-search-tv.nix
    ../modules/home/programs/obs-studio.nix
    # ../modules/home/programs/obsidian.nix
    ../modules/home/programs/opencode.nix
    ../modules/home/programs/openstackclient.nix
    ../modules/home/programs/pandoc.nix
    ../modules/home/programs/ripgrep.nix
    ../modules/home/programs/ssh.nix
    ../modules/home/programs/sftpman.nix
    ../modules/home/programs/television.nix
    ../modules/home/programs/tex-fmt.nix
    ../modules/home/programs/texlive.nix
    ../modules/home/programs/tiny.nix
    ../modules/home/programs/tmux.nix
    ../modules/home/programs/uv.nix
    ../modules/home/programs/vim.nix
    ../modules/home/programs/vscode.nix
    ../modules/home/programs/yazi.nix
    ../modules/home/programs/zed.nix
    ../modules/home/programs/zellij.nix
    ../modules/home/programs/zoxide.nix
    ../modules/home/programs/zsh
  ];

  home = {
    username = "mfarabi";
    stateVersion = "25.05";
    homeDirectory = "/home/mfarabi";

    packages = with pkgs; [
      ttyd
      arion
      hydra
      nix-ld
      argocd
      kubectl
      # microk8s
      minikube
      tailscale
      tscli
      # fw-fanctrl
      wl-screenrec
      framework-tool
      argocd-autopilot
      nvtopPackages.amd
      argocd-vault-plugin
    ];
  };

  targets.genericLinux.enable = true;
  programs.docker-cli = {
    enable = true;
    # configDir = "";
    # settings = { };
  };

  services.podman = {
    enable = true;
    enableTypeChecks = true;
    autoUpdate.enable = true;
    # networks = { };
    # images = { };
    # containers = { };
    # volumes = { };
    # builds = { };
    # settings = {
    #   containers = { };
    #   mounts = [ ];
    #   policy = { };
    #   storage = { };
    # };
  };
}

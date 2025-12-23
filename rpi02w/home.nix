{
  pkgs,
  ...
}:

{
  imports = [
    ../modules/home/programs/neovim

    ../modules/home/home.nix
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
    ../modules/home/programs/grep.nix
    ../modules/home/programs/home-manager.nix
    ../modules/home/programs/info.nix
    ../modules/home/programs/jq.nix
    ../modules/home/programs/jqp.nix
    ../modules/home/programs/lazydocker.nix
    ../modules/home/programs/lazygit.nix
    ../modules/home/programs/lazysql.nix
    ../modules/home/programs/less.nix
    ../modules/home/programs/man.nix
    ../modules/home/programs/neovim
    ../modules/home/programs/nh.nix
    ../modules/home/programs/nix-index.nix
    ../modules/home/programs/nix-search-tv.nix
    ../modules/home/programs/ripgrep.nix
    ../modules/home/programs/ssh.nix
    ../modules/home/programs/sftpman.nix
    ../modules/home/programs/television.nix
    ../modules/home/programs/tiny.nix
    ../modules/home/programs/uv.nix
    ../modules/home/programs/vim.nix
    ../modules/home/programs/yazi.nix
    ../modules/home/programs/zellij.nix
    ../modules/home/programs/zoxide.nix
    ../modules/home/programs/zsh
  ];

  home = {
    username = "mfarabi";
    stateVersion = "25.05";
    homeDirectory = "/home/mfarabi";

    packages = with pkgs; [
      tree
      pixi # multi-language package manager
      pnpm
      nodejs_24
      # =============
      ttyd
      nix-ld
      sqlite
      tgpt
      pik
      cargo-seek
      cachix
      coreutils
      platformio
      cowsay       # ascii cow
      lolcat       # rainbow text output
      figlet       # fancy ascii text output
      cmatrix      # matrix animation
      nyancat      # rainbow flying cat
      asciiquarium # ascii aquarium
      # ============= 🧑‍💻🐞✨‍ ================
      ugm           # user group management
      isd           # systemd units
      dysk          # see mounted
      kmon          # kernel monitor
      termshark     # wireshark-like TUI
      systeroid     # powerful sysctl alternative
      netscanner
      lazyjournal   # journal logs
      systemctl-tui # systemctl logs
    ];
  };

  targets.genericLinux.enable = true;
  programs.docker-cli = {
    enable = true;
    # configDir = "";
    # settings = { };
  };
}


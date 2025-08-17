{ pkgs, ... }:
{
  home = {
    stateVersion = "25.05";
    username = "mfarabi";
    packages = with pkgs; [
      # ============== 🤪 =================
      asciiquarium
      cowsay
      cmatrix
      figlet
      nyancat
      lolcat
      # hollywood
      # ============= 🧑‍💻🐞‍ ================
      # pnpm
      devenv
      nix-inspect
      tgpt
      # ugm
      lazyjournal
      pik
      systemctl-tui
      # virt-viewer
      # ===================
      zsh-powerlevel10k
      meslo-lgs-nf
    ];

    shell = {
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    language = {
      base = "en_US";
    };
  };

  nix = {
    gc = {
      automatic = true;
      frequency = "daily";
      persistent = true;
    };
  };
}

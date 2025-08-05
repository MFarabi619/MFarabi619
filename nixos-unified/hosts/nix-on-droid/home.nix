{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../nixos-unified/modules/home/programs/home-manager.nix
    ../../nixos-unified/modules/home/programs/lazydocker.nix
    ../../nixos-unified/modules/home/programs/lazysql.nix
    ../../nixos-unified/modules/home/programs/btop.nix
    ../../nixos-unified/modules/home/programs/bat.nix
    ../../nixos-unified/modules/home/programs/fd.nix
    ../../nixos-unified/modules/home/programs/fzf.nix
    ../../nixos-unified/modules/home/programs/direnv.nix
    ../../nixos-unified/modules/home/programs/jq.nix
    ../../nixos-unified/modules/home/programs/go.nix
    ../../nixos-unified/modules/home/programs/eza.nix
    ../../nixos-unified/modules/home/programs/zellij.nix
    ../../nixos-unified/modules/home/programs/ripgrep.nix
    ../../nixos-unified/modules/home/programs/nix-index.nix
    ../../nixos-unified/modules/home/programs/pandoc.nix
    ../../nixos-unified/modules/home/programs/texlive.nix
    ../../nixos-unified/modules/home/programs/tex-fmt.nix
    ../../nixos-unified/modules/home/programs/nh.nix
    ../../nixos-unified/modules/home/programs/k9s.nix
    ../../nixos-unified/modules/home/programs/kubecolor.nix
    ../../nixos-unified/modules/home/programs/yazi.nix
    ../../nixos-unified/modules/home/gc.nix
    ../../nixos-unified/modules/home/manual.nix
    ../../nixos-unified/modules/home/shell.nix
  ];

  home = {
    stateVersion = "24.05";
    packages = with pkgs; [
    ];
  };
  programs = {
    git = {
      enable = true;
      userName = "Mumtahin Farabi";
      userEmail = "mfarabi619@gmail.com";
      ignores = [ "*~" "*.swp" ];
        extraConfig = {
          init.defaultBranch = "main";
          pull.rebase = false;
        };
    };
    lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui = {
          nerdFontsVersion = "3";
          parseEmoji = true;
          scrollPastBottom = true;
          scrollOffBehaviour = "jump";
          sidePanelWidth = 0.33;
          switchTabsWithPanelJumpKeys = true;
        };
        os = {
          edit = "emacsclient -n {{filename}}";
          editAtLine = "emacsclient -n +{{line}} {{filename}}";
          openDirInEditor = "emacsclient {{dir}}";
          editInTerminal = false;
        };
        git = {
          commit.signOff = true;
          branchPrefix = "mfarabi/";
        };
        promptToReturnFromSubprocess = true;
      };
    };
  };
}

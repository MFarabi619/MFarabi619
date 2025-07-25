{
  inputs,
  config,
  pkgs,
  ...
}:

{

  imports = [
    inputs.lazyvim.homeManagerModules.default
    inputs.nix-doom-emacs-unstraightened.homeModule
    ../../../../modules/home/doom-emacs.nix
    ../../../../modules/home/progams
  ];

  home = {
    username = "mfarabi";
    homeDirectory = "/home/mfarabi";
    stateVersion = "25.05";
    packages = with pkgs; [
      # ==========  Doom Emacs ===========
      # clang
      cmake # vterm compilation and more
      coreutils
      # binutils      # native-comp needs 'as', provided by this
      gnutls # for TLS connectivity
      epub-thumbnailer # dired epub previews
      poppler-utils # dired pdf previews
      openscad
      openscad-lsp
      vips # dired image previews
      imagemagick # for image-dired
      tuntox # collab
      sqlite # :tools lookup & :lang org +roam
      ispell # spelling
      nil # nix lang formatting
      shellcheck # shell script formatting
      # texlive     # :lang latex & :lang org (latex previews)
      # ============== 🤪 =================
      asciiquarium
      cowsay
      cmatrix
      figlet
      nyancat
      lolcat
      hollywood
      # ============= 🧑‍💻🐞‍ ================
      # pnpm
      devenv
      nix-inspect
      tgpt
      kmon
      ugm
      lazyjournal
      pik
      netscanner
      systemctl-tui
      virt-viewer
      # ===================
      zsh-powerlevel10k
    ];
  };

  programs = {
    neovim.enable = true;
    lazyvim = {
      enable = true;
      extras = {
        ui = {
          mini-animate.enable = true;
        };
        editor = {
          fzf.enable = true;
        };
        test.core.enable = true;
        lang = {
          nix.enable = true;
          json.enable = true;
          markdown.enable = true;
          tailwind.enable = true;
          typescript.enable = true;
          python.enable = true;
        };
        dap.core.enable = true;
      };
    };
    zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      oh-my-zsh = {
        enable = true;
        # theme = "powerlevel10k/powerlevel10k";
        plugins = [
          "sudo"
          "git"
        ];
      };
      shellAliases = {
        cat = "bat";
      };
    };
    superfile.enable = true;
    mu.enable = true;
    nh.enable = true;
    java.enable = true;
  };
}

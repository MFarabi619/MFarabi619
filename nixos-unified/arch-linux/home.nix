{
  inputs,
  config,
  pkgs,
  ...
}:

{
  targets.genericLinux.enable = true;
  imports = [
    ../modules/home/services
    ../modules/home/manual.nix
    ../modules/home/packages.nix
    ../modules/home/editorconfig.nix
    ../modules/home/programs/doom
    ../modules/home/programs/bat.nix
    ../modules/home/programs/btop.nix
    ../modules/home/programs/command-not-found.nix
    ../modules/home/programs/chromium.nix
    ../modules/home/programs/eza.nix
    ../modules/home/programs/fd.nix
    ../modules/home/programs/fzf.nix
    ../modules/home/programs/gh.nix
    ../modules/home/programs/git.nix
    ../modules/home/programs/grep.nix
    ../modules/home/programs/gpg.nix
    ../modules/home/programs/go.nix
    ../modules/home/programs/home-manager.nix
    ../modules/home/programs/direnv.nix
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
    ../modules/home/programs/pandoc.nix
    ../modules/home/programs/ripgrep.nix
    ../modules/home/programs/television.nix
    ../modules/home/programs/tex-fmt.nix
    ../modules/home/programs/texlive.nix
    ../modules/home/programs/uv.nix
    ../modules/home/programs/vim.nix
    ../modules/home/programs/yazi.nix
    ../modules/home/programs/zsh
    ../modules/home/programs/zed.nix
    ../modules/home/programs/zellij.nix
    ../modules/home/programs/zoxide.nix
  ];

  programs = {
    nh = {
      flake = ./.;
    };
  };


  home = {
    username = "mfarabi";
    stateVersion = "25.05";
    homeDirectory = "/home/mfarabi";
    shell = {
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    packages = with pkgs; [
      #  It's sometimes useful to fine-tune packages, for example, by applying
      #  overrides. You can do that directly here, just don't forget the
      #  parentheses. Maybe you want to install Nerd Fonts with a limited number of
      #  fonts?
      # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

      # simple shell scripts
      (writeShellScriptBin "my-hello" ''
        echo "Hello, ${config.home.username}!"
      '')
    ];
    file = {
      # Building this configuration will create a copy of 'dotfiles/screenrc' in
      # the Nix store. Activating the configuration will then make '~/.screenrc' a
      # symlink to the Nix store copy.
      # .screenrc".source = dotfiles/screenrc;

      ".config/surfingkeys/.surfingkeys.js" = {
        enable = true;
        source = ../modules/home/programs/.surfingkeys.js;
      };
    };

    # Home Manager can also manage your environment variables through
    # 'home.sessionVariables'. These will be explicitly sourced when using a
    # shell provided by Home Manager. If you don't want to manage your shell
    # through Home Manager then you have to manually source 'hm-session-vars.sh'
    # located at either
    #
    #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
    # or
    #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
    # or
    #  /etc/profiles/per-user/mfarabi/etc/profile.d/hm-session-vars.sh
    # sessionVariables = {
    # EDITOR = "emacs";
    # };
  };
}

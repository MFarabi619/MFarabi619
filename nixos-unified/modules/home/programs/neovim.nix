{
  pkgs,
  ...
}:

{
  imports = [
    # ./nixvim.nix
  ];
  # programs.nixvim.enable = true;
  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
    };
    lazyvim = {
      enable = true;
      plugins = with pkgs; [
        vimPlugins.base16-nvim
      ];
      extras = {
        # test.core.enable = true;
        dap.core.enable = true;
        linting.eslint.enable = true;
        ui.mini-animate.enable = true;
        ai = {
          copilot-chat.enable = false;
          copilot.enable = false;
        };
        util = {
          dot.enable = true;
          # mini-hipatterns.enable = true;
        };
        editor = {
          fzf.enable = true;
          # snacks_explorer.enable = true;
          # snacks_picker.enable = true;
          # inc-rename.enable = true;
        };
        lang = {
          # astro.enable = true;
          nix.enable = true;
          json.enable = true;
          # markdown.enable = true;
          tailwind.enable = true;
          typescript.enable = true;
          python.enable = true;
          go.enable = true;
        };
      };
    };
  };
}

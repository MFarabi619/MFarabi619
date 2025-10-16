{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
    enableZshIntegration = true;
    enableBashIntegration = true;
    # keymap = {};
    # flavors = { inherit (pkgs.yaziPlugins); };
    # theme = {};
    plugins = {
      inherit (pkgs.yaziPlugins)
        git
        sudo
        lazygit
        restore
        yatline
        smart-paste
        smart-enter
        full-border
        smart-filter
        rich-preview
        # wl-clipboard
        yatline-githead
        # yatline-catppuccin
        ;
    };
    settings = {
      mgr = {
        ratio = [
          1
          4
          3
        ];
        show_hidden = true;
        show_symlink = true;
        sort_dir_first = true;
      };
      # yazi = {};
    };
    initLua = ''
      require("yatline"):setup()
      require("full-border"):setup()
      require("git"):setup()
      require("smart-enter"):setup {
      open_multi = true,
      }
    '';
  };
}

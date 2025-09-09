{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    shellWrapperName = "yy";
    # keymap = {};
    # flavors = { inherit (pkgs.yaziPlugins); };
    # theme = {};
    plugins = {
      inherit (pkgs.yaziPlugins)
        sudo
        git
        lazygit
        smart-enter
        full-border
        smart-filter
        rich-preview
        # wl-clipboard
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
      require("full-border"):setup()
      require("git"):setup()
      require("smart-enter"):setup {
      open_multi = true,
      }
    '';
  };
}

{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    plugins = {
      lazygit = pkgs.yaziPlugins.lazygit;
      full-border = pkgs.yaziPlugins.full-border;
      git = pkgs.yaziPlugins.git;
      smart-enter = pkgs.yaziPlugins.smart-enter;
    };
    settings = {
      manager = {
        ratio = [
          1
          4
          3
        ];
        show_hidden = true;
        show_symlink = true;
        sort_dir_first = true;
      };
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

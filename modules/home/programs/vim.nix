{ pkgs, ... }:
{
  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      vim-nix
      vim-lastplace
    ];
    settings = {
      background = "dark";
      expandtab = true;
      ignorecase = true;
      modeline = true;
      relativenumber = true;
      shiftwidth = 4;
      smartcase = true;
    };
    extraConfig = ''
      syntax on
      set tabstop=4
      set autoindent
      set smartindent
      set colorcolumn=80
      colorscheme habamax
      cmap w!! w !sudo tee > /dev/null %
      set backspace=indent,eol,start
    '';
  };
}

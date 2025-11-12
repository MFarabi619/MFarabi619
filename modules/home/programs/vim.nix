{ pkgs, ... }:
{
  programs.vim = {
    enable = true;

    plugins = with pkgs.vimPlugins; [
      vim-nix
      vim-lastplace
    ];

    settings = {
      shiftwidth = 4;
      modeline = true;
      smartcase = true;
      expandtab = true;
      ignorecase = true;
      background = "dark";
      relativenumber = true;
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

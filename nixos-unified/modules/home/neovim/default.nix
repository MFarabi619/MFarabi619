{ flake, pkgs, ... }:
{
  imports = [
    # flake.inputs.nixvim.homeManagerModules.nixvim
    flake.inputs.lazyvim.homeManagerModules.default
  ];

  # programs.nixvim = import ./nixvim.nix // {
  #   enable = true;
  # };

  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
    };
    lazyvim = {
      enable = true;
      plugins = with pkgs; [
        vimPlugins.base16-nvim
      ];
      extras = {
        util = {
          dot.enable = true;
        };
        ui = {
          mini-animate.enable = true;
        };
        editor = {
          fzf.enable = true;
          # neotree.enable = true;
        };
        test.core.enable = true;
        lang = {
          nix.enable = true;
          json.enable = true;
          # markdown.enable = true;
          tailwind.enable = true;
          typescript.enable = true;
          python.enable = true;
        };
        dap.core.enable = true;
      };
    };
  };
}

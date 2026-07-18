{
  programs.lazyvim = {
    extras = {
      dap.core.enable = true;
      test.core.enable = true;

      ui = {
        edgy.enable = true;
        mini-animate.enable = true;
        dashboard-nvim.enable = true;
        mini-indentscope.enable = true;
        treesitter-context.enable = true;
      };

      editor = {
        aerial.enable = true;
        overseer.enable = true;
        neo-tree.enable = false;
        telescope.enable = true;
        refactoring.enable = true;
      };

      coding = {
        yanky.enable = true;
        luasnip.enable = false;
        mini-comment.enable = true;
        mini-surround.enable = true;
      };

      lang = {
        tex.enable = true;
        json.enable = true;
        toml.enable = true;
        yaml.enable = true;
        markdown.enable = true;

        go.enable = true;
        git.enable = true;
        nix.enable = true;
        sql.enable = true;
        rust.enable = true;
        ruby.enable = true;
        cmake.enable = true;
        clangd.enable = true;
        python.enable = true;
        docker.enable = false;
        tailwind.enable = true;
        typescript.enable = true;
      };

      util = {
        octo.enable = true;
        rest.enable = true;
        project.enable = true;
        startuptime.enable = true;
        mini-hipatterns.enable = true;
      };
    };

    # treesitterParsers = with pkgs.tree-sitter-grammars; [
    #   tree-sitter-nix
    #   tree-sitter-kdl
    #   tree-sitter-python
    # ];

    # extraPackages = with pkgs; [
    #   nixd
    #   alejandra

    #   black
    #   pyright
    # ];
  };
}

# {
#   pkgs,
#   ...
# }:
{
  programs.lazyvim = {
    extras = {
      test.core.enable = true;
      ai.copilot_chat.enable = true;

      dap = {
        core.enable = true;
        nlua.enable = false;
      };

      ui = {
        edgy.enable = true;
        mini_animate.enable = true;
        dashboard_nvim.enable = true;
        mini_indentscope.enable = true;
        treesitter_context.enable = true;
      };

      editor = {
        aerial.enable = true;
        overseer.enable = true;
        neo_tree.enable = false;
        telescope.enable = true;
        refactoring.enable = true;
      };

      coding = {
        yanky.enable = true;
        luasnip.enable = false;
        mini_comment.enable = true;
        mini_surround.enable = true;
      };

      lang = {
        tex.enable = true;
        json.enable = true;
        toml.enable = true;
        yaml.enable = true;
        markdown.enable = true;

        go.enable = false;
        git.enable = true;
        nix.enable = true;
        sql.enable = false; # FIXME: results in fixed output derivation error resulting from dadbod
        rust.enable = true;
        ruby.enable = false;
        clang.enable = true;
        cmake.enable = true;
        python.enable = true;
        docker.enable = false;
        svelte.enable = false;
        tailwind.enable = false;
        typescript.enable = true;
      };

      util = {
        gh.enable = true;
        dot.enable = false;
        octo.enable = true;
        rest.enable = true;
        project.enable = true;
        startuptime.enable = true;
        mini_hipatterns.enable = true;
      };
    };

    # treesitterParsers = with pkgs.tree-sitter-grammars; [
    #   tree-sitter-nix
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

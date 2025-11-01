{
  devcontainer = {
    enable = false;
    settings = {
      name = "Microvisor";
      privileged = false;
      overrideCommand = false;
      updateContentCommand = "devenv test";
      image = "ghcr.io/cachix/devenv/devcontainer:latest";
      features = {
        "ghcr.io/devcontainers/features/github-cli" = { };
      };
      customizations.vscode.extensions = [
        "antfu.vite"
        "mkhl.direnv"
        "bbenoist.nix"
        "vitest.explorer"
        "tootone.org-mode"
        "redhat.vscode-yaml"
        "timonwong.shellcheck"
        "nrwl.angular-console"
        "likec4.likec4-vscode"
        "unifiedjs.vscode-mdx"
        "esbenp.prettier-vscode"
        "graphql.vscode-graphql"
        "dbaeumer.vscode-eslint"
        "tamasfe.even-better-toml"
        "EditorConfig.EditorConfig"
        "ms-vsliveshare.vsliveshare"
        "firsttris.vscode-jest-runner"
        "github.vscode-github-actions"
        "uniquevision.vscode-plpgsql-lsp"
        "cweijan.vscode-postgresql-client2"
        "christian-kohler.npm-intellisense"
        "christian-kohler.path-intellisense"
      ];
    };
  };
}

{ pkgs, ... }:


{
  programs.vscode = {
    enable = true;
    profiles = {
      mfarabi = {
        enableUpdateCheck = true;
        enableExtensionUpdateCheck = true;
        extensions = with pkgs.vscode-extensions; [
          ms-vsliveshare.vsliveshare
          timonwong.shellcheck
          bradlc.vscode-tailwindcss
          tamasfe.even-better-toml
          github.vscode-github-actions
          graphql.vscode-graphql
          graphql.vscode-graphql-syntax
          unifiedjs.vscode-mdx
          bbenoist.nix
          jnoortheen.nix-ide
          christian-kohler.npm-intellisense
          christian-kohler.path-intellisense
          esbenp.prettier-vscode
          bierner.markdown-mermaid

          # solidity
          # supabase
          # unocss
          # vitest
          # docker
          # drizzle orm
          # github repositories
          # iconify intellisense
          # ksl
          # markdownlint
          # org mode
          # playwright test for vscode
          # postgresql lsp
          # pulumi
          # pulumi copilot
          # pulumi yaml
          ms-vscode-remote.vscode-remote-extensionpack
          antfu.slidev
          # sway
          vscodevim.vim
          vue.volar
          vue.vscode-typescript-vue-plugin
          # vite
          # ms-vscode-remote.remote-wsl
          # xstate vscode
          ms-kubernetes-tools.vscode-kubernetes-tools
        ];
        userSettings = {
          editor = {
            minimap = {
              enabled = true;
            };
            wordWrap = "on";
            files = {
              autoSave = "afterDelay";
            };
          };
          workbench = {
            panel = {
              showLabels = false;
            };
            sideBar = {
              location = "right";
            };
            navigationControl = {
              enabled = false;
            };
            layoutControl = {
              enabled = false;
            };
          };
          window = {
            titleBarStyle = "native";
            customTitleBarVisibility = "windowed";

          };
          zenMode = {
            showTabs = "single";
          };
          terminal = {
            integrated = {
              enableImages = true;
            };
          };
          github.copilot.enable = {
            "*" = false;
            plaintext = false;
            markdown = false;
            scminput = false;
          };
        };
        userTasks = {

        };
        keybindings = [
          {
            key = "ctrl+c";
            command = "editor.action.clipboardCopyAction";
            when = "textInputFocus";
          }
        ];
      };
    };
  };
}

{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    profiles = {
      default = {
        enableUpdateCheck = true;
        enableExtensionUpdateCheck = true;
      };

      mfarabi = {
        userTasks = {};

        keybindings = [
          {
            key = "ctrl+c";
            command = "editor.action.clipboardCopyAction";
            when = "textInputFocus";
          }
        ];

        extensions = with pkgs.vscode-extensions; [
          vue.volar
          antfu.slidev
          bbenoist.nix
          vscodevim.vim
          jnoortheen.nix-ide
          unifiedjs.vscode-mdx
          timonwong.shellcheck
          esbenp.prettier-vscode
          graphql.vscode-graphql
          tamasfe.even-better-toml
          bierner.markdown-mermaid
          bradlc.vscode-tailwindcss
          ms-vsliveshare.vsliveshare
          tailscale.vscode-tailscale
          github.vscode-github-actions
          graphql.vscode-graphql-syntax
          platformio.platformio-vscode-ide
          vue.vscode-typescript-vue-plugin
          christian-kohler.npm-intellisense
          christian-kohler.path-intellisense
          ms-vscode-remote.vscode-remote-extensionpack
          ms-kubernetes-tools.vscode-kubernetes-tools

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
          # sway
          # vite
          # ms-vscode-remote.remote-wsl
          # xstate vscode
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
      };
    };
  };
}

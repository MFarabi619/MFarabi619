{pkgs,...}:

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
# solidity
# supabase
# tailwind
# unocss
# vitest
# docker
# drizzle orm
# even better toml
# github actions
# github repositories
# graphql lsp
# graphql syntax highlighting
# iconify intellisense
# ksl
# markdownlint
# mdx
# nix
# npm intellisense
# org mode
# path intellisense
# playwright test for vscode
# postgresql lsp
# prettier
# pulumi
# pulumi copilot
# pulumi yaml
# remote tunnels
# remote explorer
# remote repositories
# slidev
# sway
# vim
# vite
# vue
# wsl
# xstate vscode
# kubernetes
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
keybindings = {

};
};
};
};
}

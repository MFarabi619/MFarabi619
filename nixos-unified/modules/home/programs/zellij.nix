{
  home.shellAliases.zlj = "zellij";
  programs.zellij = {
    enable = true;
    # themes = { };
    exitShellOnExit = false;
    enableBashIntegration = true;
    enableZshIntegration = false;
    attachExistingSession = true;
    settings = {
      mouse_mode = true;
      mirror_session = true;
      theme = "gruvbox-dark";
      default_mode = "normal";
      show_startup_tips = false;
      show_release_notes = false;
      ui.pane_frames.hide_session_name = true;
      # load_plugins = [
          # "file:/path/to/my-plugin.wasm"
          # "https://example.com/my-plugin.wasm"
      # ];
    };
    layouts = {
      dev = {
        layout = {
          _children = [
            {
              default_tab_template = {
                _children = [
                  {
                    pane = {
                      size = 1;
                      borderless = true;
                      plugin = {
                        location = "zellij:tab-bar";
                      };
                    };
                  }
                  { "children" = { }; }
                  {
                    pane = {
                      size = 2;
                      borderless = true;
                      plugin = {
                        location = "zellij:status-bar";
                      };
                    };
                  }
                ];
              };
            }
            {
              tab = {
                _props = {
                  name = "SHELL";
                  focus = true;
                };
                _children = [
                  {
                    pane = {
                      command = "fastfetch";
                    };
                  }
                ];
              };
            }
            {
              tab = {
                _props = {
                  name = "STATUS";
                };
                _children = [
                  {
                    pane = {
                      command = "lazygit";
                    };
                  }
                ];
              };
            }
            {
              tab = {
                _props = {
                  name = "FILES";
                };
                _children = [
                  {
                    pane = {
                      command = "yazi";
                    };
                  }
                ];
              };
            }
          ];
        };
      };
    };
  };
}

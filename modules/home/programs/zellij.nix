{
  pkgs,
  ...
}:
{
  programs.zellij = {
    enable = true;
    exitShellOnExit = false;
    enableZshIntegration = false;
    enableBashIntegration = false;
    # NOTE: trace: warning: mfarabi profile: You have enabled `programs.zellij.attachExistingSession`, but none of the shell integrations are enabled. This option will have no effect.
    # attachExistingSession = true;

    plugins = with pkgs.zellijPlugins; [ zjstatus ];

    settings = {
      mouse_mode = true;
      mirror_session = true;
      default_mode = "normal";
      focus_follows_mouse = true;
      pane_frames = false;
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
                  name = "STATUS";
                };
                _children = [
                  {
                    pane = {
                      command = "asciiquarium";
                    };
                  }
                  {
                    pane = {
                      command = "fastfetch -C examples/25.jsonc";
                    };
                  }
                  {
                    pane = {
                      command = "lazygit";
                    };
                  }
                  {
                    pane = {
                      command = "yazi";
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
                      command = "emacs -nw";
                    };
                  }
                  {
                    pane = {
                      command = "btop";
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

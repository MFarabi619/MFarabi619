{
  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    attachExistingSession = true;
    # exitShellOnExit = true;
    themes = { };
    settings = {
      ui = {
        pane_frames = {
          hide_session_name = true;
        };
      };
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

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
    # attachExistingSession = true;
    plugins = with pkgs.zellijPlugins; [ zjstatus ];

    settings = {
      default_mode = "normal";
      focus_follows_mouse = true;
    }
    // {
      pane_frames = false;
      # simplified_ui = true;
      osc8_hyperlinks = true;
      attach_to_session = true;
      session_name = "zellij-session";
      ui.pane_frames.hide_session_name = true;
    }
    // {
      show_startup_tips = false;
      show_release_notes = false;
    }
    // {
      # load_plugins = [ "file:/path/to/my-plugin.wasm" "https://example.com/my-plugin.wasm" ];
    }
    // {
      # base_url = "/";
      # web_client = true;
      # web_server = true;
      # web_sharing = "off";
      # web_server_port = 8082;
      # web_server_ip = "127.0.0.1";
    };

    layouts = {
      dev.layout._children = [
        {
          default_tab_template._children = [
            {
              pane = {
                size = 1;
                borderless = true;
                plugin.location = "zellij:tab-bar";
              };
            }
            { "children" = { }; }
            {
              pane = {
                size = 2;
                borderless = true;
                plugin.location = "zellij:status-bar";
              };
            }
          ];
        }
        {
          tab = {
            _props.name = "DEMO";
            _children = [
              { pane.command = "asciiquarium"; }
              { pane.command = "btop"; }
              {
                pane = {
                  command = "cmatrix";
                  args = [
                    "-C"
                    "yellow"
                  ];
                };
              }
            ];
          };
        }
        {
          tab = {
            _props.name = "DEMO";
            _children = [
              {
                pane = {
                  command = "sudo";
                  args = [
                    "termshark"
                    "-i"
                    "en0"
                  ];
                };
              }
              {
                pane = {
                  command = "sudo";
                  args = [
                    "bandwhich"
                    "-i"
                    "en0"
                    "-sv"
                  ];
                };
              }
            ];
          };
        }
        {
          tab = {
            _props.name = "STATUS";
            _children = [
              { pane.command = "lazygit"; }
              { pane.command = "yazi"; }
              {
                pane = {
                  command = "emacs";
                  args = [ "-nw" ];
                };
              }
            ];
          };
        }
      ];
    };
  };
}

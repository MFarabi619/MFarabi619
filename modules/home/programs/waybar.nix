{
  lib,
  pkgs,
  config,
  ...
}:
# let
#   betterTransition = "all 0.3s cubic-bezier(.55,-0.68,.48,1.682)";
# in
# with lib; {
#   programs.waybar = {
#     enable = true;
#     package = pkgs.waybar;
#     settings = [
#       {
#         layer = "top";
#         position = "top";
#         modules-center = [ "hyprland/workspaces" ];
#         modules-left = [
#           "custom/startmenu"
#           "hyprland/window"
#           "pulseaudio"
#           "cpu"
#           "memory"
#           "idle_inhibitor"
#         ];
#         modules-right = [
#           "custom/hyprbindings"
#           "custom/notification"
#           "custom/exit"
#           "battery"
#           "tray"
#           "clock"
#         ];

#         "hyprland/workspaces" = {
#           format = "{name}";
#           format-icons = {
#             default = " ";
#             active = " ";
#             urgent = " ";
#           };
#           on-scroll-up = "hyprctl dispatch workspace e+1";
#           on-scroll-down = "hyprctl dispatch workspace e-1";
#         };
#         "clock" = {
#           format = " {:L%H:%M}";
#           tooltip = true;
#           tooltip-format = "<big>{:%A, %d.%B %Y }</big>\n<tt><small>{calendar}</small></tt>";
#         };
#         "hyprland/window" = {
#           max-length = 22;
#           separate-outputs = false;
#           rewrite = {
#             "" = " 🙈 No Windows? ";
#           };
#         };
#         "memory" = {
#           interval = 5;
#           format = " {}%";
#           tooltip = true;
#         };
#         "cpu" = {
#           interval = 5;
#           format = " {usage:2}%";
#           tooltip = true;
#         };
#         "custom/gpu" = {
#           format = "GPU: {}";
#           return-type = "plain";
#           interval = 2;
#           exec = pkgs.writeShellScript "gpu-usage" ''
#             cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo "N/A"
#           '';
#         };
#         "disk" = {
#           format = " {free}";
#           tooltip = true;
#         };
#         "network" = {
#           format-icons = [
#             "󰤯"
#             "󰤟"
#             "󰤢"
#             "󰤥"
#             "󰤨"
#           ];
#           format-ethernet = " {bandwidthDownOctets}";
#           format-wifi = "{icon} {signalStrength}%";
#           format-disconnected = "󰤮";
#           tooltip = false;
#         };
#         "tray" = {
#           spacing = 12;
#         };
#         "pulseaudio" = {
#           format = "{icon} {volume}% {format_source}";
#           format-bluetooth = "{volume}% {icon} {format_source}";
#           format-bluetooth-muted = " {icon} {format_source}";
#           format-muted = " {format_source}";
#           format-source = " {volume}%";
#           format-source-muted = "";
#           format-icons = {
#             headphone = "";
#             hands-free = "";
#             headset = "";
#             phone = "";
#             portable = "";
#             car = "";
#             default = [
#               ""
#               ""
#               ""
#             ];
#           };
#           on-click = "sleep 0.1 && pavucontrol";
#         };
#         "custom/exit" = {
#           tooltip = false;
#           format = "";
#           on-click = "sleep 0.1 && wlogout";
#         };
#         "custom/startmenu" = {
#           tooltip = false;
#           format = "";
#           on-click = "sleep 0.1 && rofi-launcher";
#         };
#         "custom/hyprbindings" = {
#           tooltip = false;
#           format = "󱕴";
#           on-click = "sleep 0.1 && list-keybinds";
#         };
#         "idle_inhibitor" = {
#           format = "{icon}";
#           format-icons = {
#             activated = "";
#             deactivated = "";
#           };
#           tooltip = "true";
#         };
#         "custom/notification" = {
#           tooltip = false;
#           format = "{icon} {}";
#           format-icons = {
#             notification = "<span foreground='red'><sup></sup></span>";
#             none = "";
#             dnd-notification = "<span foreground='red'><sup></sup></span>";
#             dnd-none = "";
#             inhibited-notification = "<span foreground='red'><sup></sup></span>";
#             inhibited-none = "";
#             dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
#             dnd-inhibited-none = "";
#           };
#           return-type = "json";
#           exec-if = "which swaync-client";
#           exec = "swaync-client -swb";
#           on-click = "sleep 0.1 && task-waybar";
#           escape = true;
#         };
#         "battery" = {
#           states = {
#             warning = 30;
#             critical = 5;
#           };
#           format = "{icon} {capacity}%";
#           format-charging = "󰂄 {capacity}%";
#           format-plugged = "󱘖 {capacity}%";
#           format-icons = [
#             "󰁺"
#             "󰁻"
#             "󰁼"
#             "󰁽"
#             "󰁾"
#             "󰁿"
#             "󰂀"
#             "󰂁"
#             "󰂂"
#             "󰁹"
#           ];
#           tooltip = false;
#         };
#       }
#     ];
#     style = ''
#       * {
#         font-family: JetBrainsMono Nerd Font Mono;
#         font-size: 16px;
#         border-radius: 0px;
#         border: none;
#         min-height: 0px;
#       }
#       window#waybar {
#         background: rgba(0,0,0,0);
#       }
#       #workspaces {
#         color: #f0f0f0;
#         background: #333333;
#         margin: 4px 4px;
#         padding: 5px 5px;
#         border-radius: 16px;
#       }
#       #workspaces button {
#         font-weight: bold;
#         padding: 0px 5px;
#         margin: 0px 3px;
#         border-radius: 16px;
#         color: #f0f0f0;
#         background: linear-gradient(45deg, #ff5733, #ffbd33);
#         opacity: 0.5;
#         transition: ${betterTransition};
#       }
#       #workspaces button.active {
#         opacity: 1.0;
#       }
#       #workspaces button:hover {
#         opacity: 0.8;
#       }
#       tooltip {
#         background: #f0f0f0;
#         border: 1px solid #ff5733;
#         border-radius: 12px;
#       }
#       tooltip label {
#         color: #ff5733;
#       }
#       #window, #pulseaudio, #cpu, #memory, #idle_inhibitor {
#         font-weight: bold;
#         margin: 4px 0px;
#         margin-left: 7px;
#         padding: 0px 18px;
#         background: #333333;
#         color: #f0f0f0;
#         border-radius: 24px 10px 24px 10px;
#       }
#       #custom-startmenu {
#         color: #66cc66;
#         background: #444444;
#         font-size: 28px;
#         margin: 0px;
#         padding: 0px 30px 0px 5px;
#         border-radius: 0px 0px 40px 0px;
#       }
#       #custom-hyprbindings, #network, #battery,
#       #custom-notification, #tray, #custom-exit {
#         font-weight: bold;
#         background: #555555;
#         color: #f0f0f0;
#         margin: 4px 0px;
#         margin-right: 7px;
#         border-radius: 10px 24px 10px 24px;
#         padding: 0px 18px;
#       }
#       #clock {
#         font-weight: bold;
#         color: #0D0E5;
#         background: linear-gradient(90deg, #66cc66, #33cc33);
#         margin: 0px;
#         padding: 0px 5px 0px 30px;
#         border-radius: 0px 0px 0px 40px;
#       }
#     '';
#   };
# }
let
  terminal = "kitty";
  base00 = "1D2021";
  base01 = "282828";
  base03 = "504945";
  base05 = "EBDBB2";
  base06 = "FBF1C7";
  base07 = "F2E5BC";
  base08 = "FB4934";
  base09 = "FE8019";
  base0A = "FABD2F";
  base0B = "B8BB26";
  base0C = "8EC07C";
  base0D = "83A598";
  base0E = "D3869B";
  base0F = "D65D0E";
in
with lib;
{
  programs.waybar = lib.mkIf pkgs.stdenv.isLinux {
    enable = config.wayland.enable;
    systemd = {
      enable = true;
      enableDebug = false;
      enableInspect = false;
    };

    settings = [
      {
        layer = "top";
        position = "top";

        modules-left = [
          "custom/startmenu"
          "tray"
          "hyprland/window"
        ];
        modules-center = [ "hyprland/workspaces" ];
        modules-right = [
          "idle_inhibitor"
          "custom/notification"
          "pulseaudio"
          "battery"
          "clock"
          "custom/exit"
        ];

        "hyprland/workspaces" = {
          format = "{name}";
          format-icons = {
            default = " ";
            active = " ";
            urgent = " ";
          };
          on-scroll-up = "hyprctl dispatch workspace e+1";
          on-scroll-down = "hyprctl dispatch workspace e-1";
        };
        "clock" = {
          format = " {:%H:%M}";
          # ''{: %I:%M %p}'';
          tooltip = true;
          tooltip-format = "<big>{:%A, %d.%B %Y }</big><tt><small>{calendar}</small></tt>";
        };
        "hyprland/window" = {
          max-length = 60;
          separate-outputs = false;
        };
        "memory" = {
          interval = 5;
          format = " {}%";
          tooltip = true;
          on-click = "${terminal} -e btop";
        };
        "cpu" = {
          interval = 5;
          format = " {usage:2}%";
          tooltip = true;
          on-click = "${terminal} -e btop";
        };
        "disk" = {
          format = " {free}";
          tooltip = true;
          # Not working with zaneyos window open then closes
          #on-click = "${terminal} -e sh -c df -h ; read";
        };
        "network" = {
          format-icons = [
            "󰤯"
            "󰤟"
            "󰤢"
            "󰤥"
            "󰤨"
          ];
          format-ethernet = " {bandwidthDownBits}";
          format-wifi = " {bandwidthDownBits}";
          format-disconnected = "󰤮";
          tooltip = false;
          on-click = "${terminal} -e btop";
        };
        "tray" = {
          spacing = 12;
        };
        "pulseaudio" = {
          format = "{icon} {volume}% {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          format-muted = " {format_source}";
          format-source = " {volume}%";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "pavucontrol";
        };
        "custom/exit" = {
          tooltip = false;
          format = "⏻";
          on-click = "sleep 0.1 && wlogout";
        };
        "custom/startmenu" = {
          tooltip = false;
          format = " ";
          # exec = "rofi -show drun";
          on-click = "rofi -show drun";
        };
        "idle_inhibitor" = {
          format = "{icon}";
          format-icons = {
            activated = " ";
            deactivated = " ";
          };
          tooltip = "true";
        };
        "custom/notification" = {
          tooltip = false;
          format = "{icon} {}";
          format-icons = {
            notification = "<span foreground='red'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
            dnd-inhibited-none = "";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t";
          escape = true;
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 5;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󱘖 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          on-click = "";
          tooltip = false;
        };
      }
    ];
    style = concatStrings [
      ''
        * {
          font-size: 12pt;
          font-family: JetBrainsMono Nerd Font, Font Awesome, sans-serif;
          font-weight: bold;
        }
        window#waybar {
          /*
            background-color: rgba(26,27,38,0);
            border-bottom: 1px solid rgba(26,27,38,0);
            border-radius: 0px;
            color: #${base0F};
          */

          background-color: rgba(26,27,38,0);
          border-bottom: 1px solid rgba(26,27,38,0);
          border-radius: 0px;
          color: #${base0F};
        }
        #workspaces {
          /*
            Eternal
            background: linear-gradient(180deg, #${base00}, #${base01});
            margin: 5px 5px 5px 0px;
            padding: 0px 10px;
            border-radius: 0px 5px 5px 0px;
            border: 0px;
            font-style: normal;
            color: #${base00};
          */
          background: linear-gradient(45deg, #${base01}, #${base01});
          margin: 5px;
          padding: 0px 1px;
          border-radius: 5px;
          border: 0px;
          font-style: normal;
          color: #${base00};
        }
        #workspaces button {
          padding: 0px 5px;
          margin: 4px 3px;
          border-radius: 5px;
          border: 0px;
          color: #${base00};
          background: linear-gradient(45deg, #${base0D}, #${base0E});
          opacity: 0.5;
          transition: all 0.3s ease-in-out;
        }
        #workspaces button.active {
          padding: 0px 5px;
          margin: 4px 3px;
          border-radius: 5px;
          border: 0px;
          color: #${base00};
          background: linear-gradient(45deg, #${base0D}, #${base0E});
          opacity: 1.0;
          min-width: 40px;
          transition: all 0.3s ease-in-out;
        }
        #workspaces button:hover {
          border-radius: 5px;
          color: #${base00};
          background: linear-gradient(45deg, #${base0D}, #${base0E});
          opacity: 0.8;
        }
        tooltip {
          background: #${base00};
          border: 1px solid #${base0E};
          border-radius: 5px;
        }
        tooltip label {
          color: #${base07};
        }
        #window {
          /*
            Eternal
            color: #${base05};
            background: #${base00};
            border-radius: 5px;
            margin: 5px;
            padding: 2px 20px;
          */
          margin: 5px;
          padding: 2px 20px;
          color: #${base05};
          background: #${base01};
          border-radius: 5px 5px 5px 5px;
        }
        #memory {
          color: #${base0F};
          /*
            Eternal
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 5px;
            padding: 2px 20px;
          */
          background: #${base01};
          margin: 5px;
          padding: 2px 20px;
          border-radius: 5px 5px 5px 5px;
        }
        #clock {
          color: #${base0B};
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 5px;
            padding: 2px 20px;
        }
        #idle_inhibitor {
          color: #${base0A};
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 3px;
            padding: 2px 20px;
        }
        #cpu {
          color: #${base07};
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 5px;
            padding: 2px 20px;
        }
        #disk {
          color: #${base0F};
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 5px;
            padding: 2px 20px;
        }
        #battery {
          color: #${base08};
          background: #${base00};
          border-radius: 5px 5px 5px 5px;
          margin: 5px;
          padding: 2px 20px;
        }
        #network {
          color: #${base09};
          background: #${base00};
          border-radius: 5px 5px 5px 5px;
          margin: 5px;
          padding: 2px 20px;
        }
        #tray {
          color: #${base05};
          background: #${base00};
          border-radius: 5px 5px 5px 5px;
          margin: 5px;
          padding: 2px 5px;
        }
        #pulseaudio {
          color: #${base0D};
          /*
            Eternal
            background: #${base00};
            border-radius: 5px 5px 5px 5px;
            margin: 5px;
            padding: 2px 20px;
          */
          background: #${base01};
          margin: 4px;
          padding: 2px 20px;
          border-radius: 5px 5px 5px 5px;
        }
        #custom-notification {
          color: #${base0C};
          background: #${base00};
          border-radius: 5px 5px 5px 5px;
          margin: 5px;
          padding: 2px 20px;
        }
        #custom-startmenu {
          color: #${base0E};
          background: #${base00};
          border-radius: 0px 5px 5px 0px;
          margin: 5px 5px 5px 0px;
          padding: 2px 20px;
        }
        #idle_inhibitor {
          color: #${base09};
          background: #${base00};
          border-radius: 5px 5px 5px 5px;
          margin: 5px;
          padding: 2px 20px;
        }
        #custom-exit {
          color: #${base0E};
          background: #${base00};
          border-radius: 5px 0px 0px 5px;
          margin: 5px 0px 5px 5px;
          padding: 2px 20px;
        }
      ''
    ];
  };
}

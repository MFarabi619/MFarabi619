{
  config,
  ...
}:
{
  programs.television = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    settings = {
      tick_rate = 50;
      default_channel = if config.programs.nix-search-tv.enable then "nix-search-tv" else "files";

      ui = {
        ui_scale = 120;
        scrollbar = true;
        theme = "gruvbox dark";
        orientation = "landscape";
        use_nerd_font_icons = true;
      };

      actions = {
        edit = {
          mode = "fork";
          command = "nvim '{}'";
          description = "Open selected file in editor";
        };
      };

      keybindings = {
        ctrl-g = "quit";
        alt-x = "toggle_help";
        ctrl-enter = "actions:edit";
      };
    };

      channels = {
        platformio = {
          metadata = {
            name = "pio";
            description = "PlatformIO CLI";
            requirements = [ "pio" "jq" ];
          };

          ui.preview_panel = {
            enabled = true;
            size = 60;
          };

          preview.header = "{split:\t:2}";
          preview.command = ''
            cmd="{split:\t:0}"
            sub="{split:\t:1}"

            if [ "$cmd" = "boards" ]; then
              pio boards
              exit 0
            fi

            if [ "$cmd" = "device" ] && [ "$sub" = "list-mdns" ]; then
              pio device list --mdns --json-output | jq
              exit 0
            fi

            if [ "$cmd" = "device" ] && [ "$sub" = "list-serial" ]; then
              pio device list --serial --json-output | jq
              exit 0
            fi

            pio "$cmd" "$sub" --json-output \
              | jq -r '
                  def esc($code): "\u001b[" + $code + "m";
                  def title($s): esc("1;33") + $s + esc("0");
                  def value($s): esc("0;36") + ($s | tostring) + esc("0");
                  def value_green($s): esc("0;32") + ($s | tostring) + esc("0");
                  def section($s): esc("1;35") + $s + esc("0");
                  def rpad($n): . + (" " * ($n - length));
                  def row($t; $v; $w): title($t | rpad($w)) + "  " + value($v);
                  def row_pair($pair; $w): row($pair[0]; $pair[1]; $w);

                  if (has("profile") and has("packages")) then
                    . as $root
                    | ($root.profile) as $profile
                    | [
                        ["Username", ($profile.username // "")],
                        ["Email", ($profile.email // "")],
                        [
                          "Name",
                          ([ $profile.firstname, $profile.lastname ]
                            | map(select(. != null and . != ""))
                            | join(" "))
                        ]
                      ] as $profile_rows
                    | [
                        ["User ID", ($root.user_id // "")],
                        [
                          "Expires",
                          (if ($root.expire_at | type) == "number" then
                            ($root.expire_at | strftime("%Y-%m-%d"))
                          else
                            ($root.expire_at // "")
                          end)
                        ]
                      ] as $meta_rows
                    | ($profile_rows + $meta_rows | map(.[0] | length) | max? // 0) as $w
                    | ($root.packages // []) as $packages
                    | ($packages | map((.title // .name // "Package") | length) | max? // 0) as $pw
                    | (
                        section("Profile")
                        + "\n"
                        + ($profile_rows | map(row_pair(. ; $w)) | join("\n"))
                        + "\n\n"
                        + section("Packages")
                        + "\n"
                        + (
                            if ($packages | length) == 0 then
                              row("Packages"; "None"; $w)
                            else
                              ($packages
                                | map([ (.title // .name // "Package"), (.description // "") ])
                                | map(title(.[0] | rpad($pw)) + "  " + value_green(.[1]))
                                | join("\n")
                              )
                            end
                          )
                        + "\n\n"
                        + section("Meta")
                        + "\n"
                        + ($meta_rows | map(row_pair(. ; $w)) | join("\n"))
                      )
                  else
                    . as $root
                    | ($root | to_entries | map(.value.title | length) | max? // 0) as $w
                    | $root
                    | to_entries[]
                    | row(.value.title; .value.value; $w)
                  end
                '
          '';

          source = {
            ansi = false;
            display = "{split:\t:2}";
            output = "{split:\t:0} {split:\t:1}";
            command = ''
              printf "system\tinfo\tsystem info\n"
              printf "account\tshow\taccount show\n"
              printf "device\tlist-mdns\tdevice list mdns\n"
              printf "device\tlist-serial\tdevice list serial\n"
              printf "boards\t\tboards\n"
            '';
          };
        };
      };
  };
}

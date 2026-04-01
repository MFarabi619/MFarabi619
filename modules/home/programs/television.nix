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
          requirements = [
            "pio"
            "jq"
          ];
        };

        ui.preview_panel = {
          enabled = true;
          size = 60;
        };

        preview = {
          header = "{split:\t:2}";
          command = ''
            cmd="{split:\t:0}"
            sub="{split:\t:1}"

            if [ "$cmd" = "boards" ]; then
              pio boards
              exit 0
            fi

            if [ "$cmd" = "settings" ] && [ "$sub" = "get" ]; then
              pio settings get
              exit 0
            fi

            if [ "$cmd" = "device" ] && [ "$sub" = "list-mdns" ]; then
              pio device list --mdns --json-output \
                | jq -r '
                    def esc($code): "\u001b[" + $code + "m";
                    def head($s): esc("1;33") + $s + esc("0");
                    def cell($s): esc("0;36") + ($s | tostring) + esc("0");
                    def rpad($n): . + (" " * ($n - length));

                    (if type == "array" then . else [] end) as $rows_raw
                    | ($rows_raw | map([(.type // ""), (.name // ""), (.ip // ""), (.port // "")])) as $rows
                    | ["Type", "Name", "IP", "Port"] as $hdr
                    | ($rows | map(.[0] | tostring)) as $c0
                    | ($rows | map(.[1] | tostring)) as $c1
                    | ($rows | map(.[2] | tostring)) as $c2
                    | ($rows | map(.[3] | tostring)) as $c3
                    | ($c0 + [$hdr[0]] | map(length) | max? // 0) as $w0
                    | ($c1 + [$hdr[1]] | map(length) | max? // 0) as $w1
                    | ($c2 + [$hdr[2]] | map(length) | max? // 0) as $w2
                    | ($c3 + [$hdr[3]] | map(length) | max? // 0) as $w3
                    | if ($rows | length) == 0 then
                        head("No devices found")
                      else
                        (head($hdr[0] | rpad($w0)) + "  " + head($hdr[1] | rpad($w1)) + "  " + head($hdr[2] | rpad($w2)) + "  " + head($hdr[3] | rpad($w3)))
                        + "\n"
                        + ($rows
                          | map(
                              cell(.[0] | rpad($w0)) + "  " +
                              cell(.[1] | rpad($w1)) + "  " +
                              cell(.[2] | rpad($w2)) + "  " +
                              cell(.[3] | tostring)
                            )
                          | join("\n")
                        )
                      end
                  '
              exit 0
            fi

            if [ "$cmd" = "device" ] && [ "$sub" = "list-serial" ]; then
              pio device list --serial --json-output \
                | jq -r '
                    def esc($code): "\u001b[" + $code + "m";
                    def head($s): esc("1;33") + $s + esc("0");
                    def cell($s): esc("0;36") + ($s | tostring) + esc("0");
                    def rpad($n): . + (" " * ($n - length));

                    (if type == "array" then . else [] end) as $rows_raw
                    | ($rows_raw | map([(.port // ""), (.description // ""), (.hwid // "")])) as $rows
                    | ["Port", "Description", "HWID"] as $hdr
                    | ($rows | map(.[0] | tostring)) as $c0
                    | ($rows | map(.[1] | tostring)) as $c1
                    | ($rows | map(.[2] | tostring)) as $c2
                    | ($c0 + [$hdr[0]] | map(length) | max? // 0) as $w0
                    | ($c1 + [$hdr[1]] | map(length) | max? // 0) as $w1
                    | ($c2 + [$hdr[2]] | map(length) | max? // 0) as $w2
                    | if ($rows | length) == 0 then
                        head("No devices found")
                      else
                        (head($hdr[0] | rpad($w0)) + "  " + head($hdr[1] | rpad($w1)) + "  " + head($hdr[2] | rpad($w2)))
                        + "\n"
                        + ($rows
                          | map(
                              cell(.[0] | rpad($w0)) + "  " +
                              cell(.[1] | rpad($w1)) + "  " +
                              cell(.[2] | tostring)
                            )
                          | join("\n")
                        )
                      end
                  '
              exit 0
            fi

            if [ "$cmd" = "team" ] && [ "$sub" = "list" ]; then
              pio team list --json-output \
                | jq -r '
                    def esc($code): "\u001b[" + $code + "m";
                    def head($s): esc("1;33") + $s + esc("0");
                    def cell($s): esc("0;36") + ($s | tostring) + esc("0");
                    def rpad($n): . + (" " * ($n - length));

                    (if type == "object" then . else null end) as $root
                    | (if $root == null then [] else ($root | to_entries) end) as $orgs
                    | [ $orgs[] | .key as $org | (.value // [])[] | [ $org, (.name // ""), ((.members // []) | length | tostring), (.description // "") ] ] as $rows
                    | ["Org", "Team", "Members", "Description"] as $hdr
                    | ($rows | map(.[0] | tostring)) as $c0
                    | ($rows | map(.[1] | tostring)) as $c1
                    | ($rows | map(.[2] | tostring)) as $c2
                    | ($rows | map(.[3] | tostring)) as $c3
                    | ($c0 + [$hdr[0]] | map(length) | max? // 0) as $w0
                    | ($c1 + [$hdr[1]] | map(length) | max? // 0) as $w1
                    | ($c2 + [$hdr[2]] | map(length) | max? // 0) as $w2
                    | ($c3 + [$hdr[3]] | map(length) | max? // 0) as $w3
                    | if ($rows | length) == 0 then
                        head("No teams found")
                      else
                        (head($hdr[0] | rpad($w0)) + "  " + head($hdr[1] | rpad($w1)) + "  " + head($hdr[2] | rpad($w2)) + "  " + head($hdr[3] | rpad($w3)))
                        + "\n"
                        + ($rows
                          | map(
                              cell(.[0] | rpad($w0)) + "  " +
                              cell(.[1] | rpad($w1)) + "  " +
                              cell(.[2] | rpad($w2)) + "  " +
                              cell(.[3] | tostring)
                            )
                          | join("\n")
                        )
                      end
                  '
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
              printf "team\tlist\tteam list\n"
              printf "device\tlist-mdns\tdevice list mdns\n"
              printf "device\tlist-serial\tdevice list serial\n"
              printf "settings\tget\tsettings get\n"
              printf "boards\t\tboards\n"
            '';
          };
        };
      };
    };
  };
}

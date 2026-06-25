{ lib, config, ... }:
{
  tasks = lib.mkMerge [
    (lib.mapAttrs'
      (
        board: spec:
        lib.nameValuePair "build:firmware:${lib.replaceStrings [ "." "@" ] [ "_" "_" ] board}" {
          cwd = "${config.git.root}";
          exec = lib.concatStringsSep " " (
            [
              "west build apps/firmware"
              "--board ${lib.replaceStrings [ "." ] [ "/" ] board}"
              "--build-dir build/${lib.replaceStrings [ "." "@" ] [ "_" "_" ] board}"
            ]
            ++ lib.optional (spec.sysbuild or false) "--sysbuild"
            ++ map (s: "-S ${s}") (spec.snippets or [ ])
            ++ lib.optional (
              (spec.extra_conf or [ ]) != [ ]
            ) "-DEXTRA_CONF_FILE=${lib.concatStringsSep ";" spec.extra_conf}"
          );
        }
      )
      {
        "qemu_riscv32".extra_conf = [ "test.conf" ];
        "esp32_devkitc.esp32.procpu".snippets = [ "cyd28" ];
        "esp32s3_8048S043.esp32s3.procpu" = {
          sysbuild = true;
          snippets = [
            "espressif-psram-8M"
            "espressif-flash-16M"
          ];
        };
        "walter.esp32s3.procpu" = {
          sysbuild = true;
          snippets = [
            "wifi-credentials"
            "espressif-psram-2M"
            "espressif-flash-16M"
            "espressif-psram-wifi"
          ];
        };
        "xiao_esp32s3.esp32s3.procpu" = {
          sysbuild = true;
          snippets = [
            "wifi-credentials"
            "espressif-flash-8M"
            "espressif-psram-8M"
            "espressif-psram-wifi"
          ];
        };
        "esp32s3_devkitc.esp32s3.procpu" = {
          sysbuild = true;
          snippets = [
            "wifi-credentials"
            "espressif-flash-8M"
            "espressif-psram-8M"
            "espressif-psram-wifi"
          ];
        };
        "xiao_esp32s3.esp32s3.procpu.sense" = {
          sysbuild = true;
          snippets = [
            "wifi-credentials"
            "espressif-flash-8M"
            "espressif-psram-8M"
            "espressif-psram-wifi"
          ];
          extra_conf = [ "../../libs/zephyr-lib-sqlite/sqlite.conf" ];
        };
        "stm32f3_disco@E.stm32f303xc" = { };
      }
    )

    (lib.mapAttrs
      (_: command: {
        cwd = "${config.git.root}";
        exec = command;
      })
      {
        "build:server" = "cargo loco doctor";
        "build:ceratina-rs" = "cargo +esp bb";
        "build:ceratina" = "pio run";
        "build:web" = "dx build --ssg -rp web";
        "build:tui" = "cargo b -rp tui";
        "build:lazyzephyr" = "cargo b -rp lazyzephyr";
        "build:darwin" = "darwin-rebuild build --flake .";
        "build:robot" = "pixi run build";
      }
    )

    (builtins.listToAttrs (
      map
        (sample: {
          name = "build:zephyr-lang-zig:${sample}";
          value = {
            cwd = "${config.git.root}";
            exec = "west build libs/zephyr-lang-zig/samples/${sample} --build-dir build/zephyr_lang_zig_${sample}";
          };
        })
        [
          "bench"
          "blinky"
          "clay_tui"
          "ffi_rust_with_c"
          "hello_world"
          "led_strip"
          "sqlite"
          "tick_loop"
          "zigzag_tui"
        ]
    ))
  ];
}

{
  lib,
  config,
  ...
}:
{
  microvisor.embassy = rec {
    enable = true;
    cwd = "${config.git.root}/firmware";

    probe-rs = rec {
      presets = rec {
        default = esp32;
        # default = esp32s3;
        # default = stm32h723zg;
        # default = seeed_xiao_esp32s3;

        esp32 = {
          chip = "esp32";
          preverify = true;
          "always-print-stacktrace" = true;
        };

        seeed_xiao_esp32s3 = esp32s3 // {
          probe = "303a:1001:D8:3B:DA:74:82:E8";
        };

        esp32-s3-devkitc-1 = esp32s3 // {
          token = "rpi5-16";
          probe = "303a:1001:1C:DB:D4:40:4E:38";
          host = "ws://${server.address}:${toString server.port}";
        };

        esp32s3 = {
          chip = "esp32s3";
          preverify = true;
          "always-print-stacktrace" = true;
        };

        # cargo embassy init --chip stm32h723zg embassy-stm32-scaffold
        # cargo generate --git https://github.com/lulf/embassy-template.git -d chip=stm32h723zg
        stm32h723zg = {
          chip = "stm32h723zg";
          preverify = true;
          "always-print-stacktrace" = true;
        };
      };

      server = {
        port = 8443;
        address = "rpi5-16";
        users = [
          {
            name = "mfarabi";
            token = presets.esp32-s3-devkitc-1.token;
          }
        ];
      };
    };

    rust =
      lib.recursiveUpdate
        {
          cargo = {
            env.DEFMT_LOG = "info";
          };
        }
        (
          if probe-rs.presets.default.chip == "esp32s3" || probe-rs.presets.default.chip == "esp32" then
            {
              toolchain.channel = "esp";
              clippy.stack-size-threshold =
                if probe-rs.presets.default.chip == "esp32" then 8192 else 1024;

              cargo = rec {
                alias.blinky = "run -r --example=blinky";
                target."${build.target}".runner =
                  if probe-rs.presets.default.chip == "esp32" then
                    "espflash flash --monitor --chip esp32"
                  else
                    "probe-rs run";
                build = {
                  target =
                    if probe-rs.presets.default.chip == "esp32s3" then
                      "xtensa-esp32s3-none-elf"
                    else
                      "xtensa-esp32-none-elf";
                  rustflags = [
                    "-C"
                    "link-arg=-nostartfiles"
                  ];
                };
                unstable = {
                  "build-std" = [
                    "core"
                    "alloc"
                  ];
                };
              };
            }
          else
            {
              toolchain = {
                channel = "stable";
                components = [ "rustfmt" ];
                targets = [
                  "thumbv6m-none-eabi"
                  "thumbv7em-none-eabihf"
                  "thumbv8m.main-none-eabihf"
                  "riscv32imac-unknown-none-elf"
                ];
              };

              cargo = rec {
                build.target = "thumbv7em-none-eabihf";
                # target."cfg(all(target_arch = \"arm\", target_os = \"none\"))".runner = "probe-rs run";
                target."${build.target}".runner = "probe-rs run";
                unstable = {
                  "build-std" = [ "core" ];
                  "build-std-features" = [ "panic_immediate_abort" ];
                };
              };
            }
        );

    wokwi = rec {
      version = 1;
      firmware = elf;
      gdbServerPort = 3333;
      elf = "${cwd}/target/${rust.cargo.build.target}/debug/firmware";

      diagram = {
        version = 1;
        editor = "wokwi";
        serialMonitor = {
          convertEol = true;
          display = "terminal";
        };

        parts = [
          {
            id = "esp";
            top = 0.59;
            left = 0.67;
            attrs.flashSize = "16";
            type = "board-esp32-s3-devkitc-1";
          }
        ];

        connections = [
          [
            "esp:TX"
            "$serialMonitor:RX"
            ""
            [ ]
          ]
          [
            "esp:RX"
            "$serialMonitor:TX"
            ""
            [ ]
          ]
        ];
      };
    };
  };

  profiles = {
    ci.module.microvisor.embassy."probe-rs".server.address = "0.0.0.0";

    hostname = {
      rpi5-16.extends = [ "ci" ];
      framework-desktop.extends = [ "ci" ];
    };
  };
}

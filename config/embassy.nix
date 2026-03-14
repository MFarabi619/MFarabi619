{
  config,
  ...
}:
{
  microvisor.embassy = {
    enable = true;
    cwd = "${config.git.root}/firmware";

    rust = {
      toolchain = "esp";
      clippy.stack-size-threshold = 1024;

      cargo = {
        env.DEFMT_LOG = "info";
        target."${config.microvisor.embassy.rust.cargo.build.target}".runner = "probe-rs run";

        build = {
          target = "xtensa-esp32s3-none-elf";
          rustflags = [
            "-C"
            "link-arg=-nostartfiles"
          ];
        };

        unstable."build-std" = [
          "core"
          "alloc"
        ];
      };
    };

    wokwi = {
      version = 1;
      gdbServerPort = 3333;
      elf = "${config.microvisor.embassy.cwd}/target/${config.microvisor.embassy.rust.cargo.build.target}/debug/firmware";
      firmware = "${config.microvisor.embassy.cwd}/target/${config.microvisor.embassy.rust.cargo.build.target}/debug/firmware";

      diagram = {
        version = 1;
        editor = "wokwi";
        parts = [
          {
            type = "board-esp32-s3-devkitc-1";
            id = "esp";
            top = 0.59;
            left = 0.67;
            attrs.flashSize = "16";
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
        serialMonitor = {
          display = "terminal";
          convertEol = true;
        };
      };
    };

    probe-rs = {
      presets.default = {
        chip = "esp32s3";
        preverify = true;
        token = "rpi5-16";
        "always-print-stacktrace" = true;
        probe = "303a:1001:1C:DB:D4:40:4E:38";
        host = "ws://${config.microvisor.embassy."probe-rs".server.address}:${
          toString config.microvisor.embassy."probe-rs".server.port
        }";
      };

      server = {
        port = 8443;
        address = "rpi5-16";
        users = [
          {
            name = "mfarabi";
            token = config.microvisor.embassy."probe-rs".presets.default.token;
          }
        ];
      };
    };

  };

  profiles = {
    ci = {
      module = {
        microvisor.embassy."probe-rs".server.address = "0.0.0.0";
      };
    };

    hostname = {
      rpi5-16 = {
        extends = [ "ci" ];
      };

      framework-desktop = {
        extends = [ "ci" ];
      };
    };
  };
}

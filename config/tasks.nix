{
  lib,
  config,
  ...
}:
{

  tasks =
    lib.attrsets.mapAttrs
      (
        _name: task:
        {
          showOutput = true;
          cwd = config.microvisor.embassy.cwd;
        }
        // task
      )
      {
        "build:firmware" = {
          exec = "cargo b -r";
        };

        "upload:firmware" = {
          exec = "cargo r -r";
          after = [ "start:remote:probe-rs" ];
        };
      }
    // {
      "dx:serve:ssg" = {
        showOutput = true;
        exec = "dx serve -p web --ssg -r"; # https://github.com/DioxusLabs/dioxus/issues/5050
      };

      # "upload:firmware:rfc2217" = {
      #   showOutput = true;
      #   after = [
      #     "start:remote:rfc2217"
      #   ];

      #   exec = ''
      #     espflash save-image \
      #       --chip ${config.microvisor.embassy.probe-rs.presets.default.chip} \
      #       --merge \
      #       target/xtensa-esp32s3-none-elf/release/firmware \
      #       target/xtensa-esp32s3-none-elf/release/firmware.bin
      #   ''
      #   + ''
      #     esptool \
      #       --verbose \
      #       --baud ${toString config.microvisor.embassy.baud} \
      #       --port ${toString config.microvisor.embassy.port} \
      #       --after ${config.microvisor.embassy.after} \
      #       --before ${config.microvisor.embassy.before} \
      #       write-flash -z 0x0 ${config.git.root}/target/xtensa-esp32s3-none-elf/release/firmware.bin
      #   '';
      # };

      "start:remote:probe-rs" = {
        showOutput = true;
        status = "nc -z ${config.microvisor.embassy.probe-rs.server.address} ${toString config.microvisor.embassy.probe-rs.server.port}";
        exec = ''
          ssh -n ${config.microvisor.embassy.probe-rs.server.address} '
          cd ~/MFarabi619 &&
          setsid devenv shell "probe-rs serve" > /dev/null 2>&1 &'
        '';
      };

      "start:remote:rfc2217" = {
        showOutput = true;
        status = "nc -vz ${config.microvisor.embassy.probe-rs.server.address} 2217";
        exec = ''
          ssh -n ${config.microvisor.embassy.probe-rs.server.address} '
            cd ~/MFarabi619 &&
            setsid devenv shell "esp_rfc2217_server /dev/ttyACM0 -p 2217 -v" > /dev/null 2>&1 &'
        '';
      };

      "stop:remote:probe-rs" = {
        showOutput = true;
        status = "! nc -vz ${config.microvisor.embassy.probe-rs.server.address} ${toString config.microvisor.embassy.probe-rs.server.port} >/dev/null 2>&1";
        exec = " ssh -n ${config.microvisor.embassy.probe-rs.server.address} 'pkill probe-rs'";
      };

      "stop:remote:rfc2217" = {
        showOutput = true;
        status = "! nc -vz ${config.microvisor.embassy.probe-rs.server.address} 2217 >/dev/null 2>&1";
        exec = "ssh -n ${config.microvisor.embassy.probe-rs.server.address} 'killall .esp_rfc2217_server-wrapped'";
      };

      # "devenv:enterShell".after = [
      #   "ports:list"
      #   ];
    };
}

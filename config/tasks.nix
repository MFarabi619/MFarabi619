{
  config,
  ...
}:
{

  tasks = {
    "dx:serve:ssg" = {
      showOutput = true;
      exec = "dx serve --ssg -r";
      # dx serve -p web --platform web --ssg -r # https://github.com/DioxusLabs/dioxus/issues/5050
    };

    "build:firmware" = {
      showOutput = true;
      cwd = "${config.git.root}/firmware";
      exec = "cargo b --release";
    };

    "image:firmware" = {
      showOutput = true;
      after = [ "build:firmware" ];
      exec = ''
        espflash save-image \
          --chip ${config.languages.rust.embassy.chip} \
          --merge \
          target/xtensa-esp32s3-none-elf/release/firmware \
          target/xtensa-esp32s3-none-elf/release/firmware.bin
      '';
    };

    "upload:firmware" = {
      showOutput = true;
      after = [
        "image:firmware"
        "start:remote:rfc2217"
      ];

      exec = ''
        esptool \
          --verbose \
          --baud ${toString config.languages.rust.embassy.baud} \
          --port ${toString config.languages.rust.embassy.port} \
          --after ${config.languages.rust.embassy.after} \
          --before ${config.languages.rust.embassy.before} \
          write-flash -z 0x0 ${config.git.root}/target/xtensa-esp32s3-none-elf/release/firmware.bin
      '';
    };

    "start:remote:rfc2217" = {
      showOutput = true;
      status = "nc -vz rpi5-16 2217";
      exec = ''
        ssh -n rpi5-16 '
          cd ~/MFarabi619 &&
          nohup devenv shell "esp_rfc2217_server /dev/ttyUSB0 -p 2217 -v" \
          > /dev/null 2>&1 &'
      '';
    };

    "stop:remote" = {
      showOutput = true;
      status = "! nc -vz rpi5-16 2217 >/dev/null 2>&1";
      exec = ''
        ssh -n rpi5-16 "killall .esp_rfc2217_server-wrapped"
      '';
    };

    # "devenv:enterShell".after = [
    #   "ports:list"
    #   ];
  };
}

# {
#   config,
#   ...
# }:
{
  microvisor.embassy = {
    enable = true;

    #   probe-rs = rec {
    #     presets = rec {
    #       # default = esp32;
    #       default = esp32s3;
    #       # default = stm32h723zg;
    #       # default = seeed_xiao_esp32s3;

    #       esp32 = {
    #         chip = "esp32";
    #         preverify = true;
    #         "always-print-stacktrace" = true;
    #       };

    #       seeed_xiao_esp32s3 = esp32s3 // {
    #         probe = "303a:1001:D8:3B:DA:74:82:E8";
    #       };

    #       esp32-s3-devkitc-1 = esp32s3 // {
    #         token = "rpi5-16";
    #         probe = "303a:1001:1C:DB:D4:40:4E:38";
    #         host = "ws://${server.address}:${toString server.port}";
    #       };

    #       esp32s3 = {
    #         chip = "esp32s3";
    #         preverify = true;
    #         "always-print-stacktrace" = true;
    #       };

    #       # cargo embassy init --chip stm32h723zg embassy-stm32-scaffold
    #       # cargo generate --git https://github.com/lulf/embassy-template.git -d chip=stm32h723zg
    #       stm32h723zg = {
    #         chip = "stm32h723zg";
    #         preverify = true;
    #         "always-print-stacktrace" = true;
    #       };
    #     };

    #     server = {
    #       port = 8443;
    #       address = "rpi5-16";
    #       users = [
    #         {
    #           name = "mfarabi";
    #           token = presets.esp32-s3-devkitc-1.token;
    #         }
    #       ];
    #     };
    #   };

    #   wokwi = rec {
    #     version = 1;
    #     firmware = elf;
    #     gdbServerPort = 3333;
    #     elf = "${config.git.root}/debug/firmware";

    #     diagram = {
    #       version = 1;
    #       editor = "wokwi";
    #       serialMonitor = {
    #         convertEol = true;
    #         display = "terminal";
    #       };

    #       parts = [
    #         {
    #           id = "esp";
    #           top = 0.59;
    #           left = 0.67;
    #           attrs.flashSize = "16";
    #           type = "board-esp32-s3-devkitc-1";
    #         }
    #       ];

    #       connections = [
    #         [
    #           "esp:TX"
    #           "$serialMonitor:RX"
    #           ""
    #           [ ]
    #         ]
    #         [
    #           "esp:RX"
    #           "$serialMonitor:TX"
    #           ""
    #           [ ]
    #         ]
    #       ];
    #     };
    #   };
  };
}

{
  config,
  ...
}:
{
  platformio = {
    enable = true;
    name = config.name;
    src_dir = "${config.git.root}/firmware";

    default_envs = [
      # "cyd"
      "walter"
      # "waveshare-esp32-s3-touch-lcd-1-47"
    ];

    envs = rec {
      # https://www.waveshare.com/wiki/ESP32-S3-Touch-LCD-1.47#Install_Library
      # waveshare-esp32-s3-touch-lcd-1-47 = base // {
      #   board = "esp32s3_120_16_8-qio_opi";
      #   board_build.flash_mode = "qio";
      #   board_build.flash_size = "16MB";

      #   lib_deps = [
      #     # "lvgl/lvgl@^9.5.0"
      #     "lovyan03/LovyanGFX@^1.1.9"
      #     "moononournation/GFX Library for Arduino@^1.6.5"
      #   ];

      #   build_flags = [
      #     "-DBOARD_HAS_PSRAM"
      #     "-DARDUINO_USB_MODE=1"
      #     "-DARDUINO_USB_CDC_ON_BOOT=1"
      #   ];
      # };

      cyd = base // {
        upload_port = "*110";
        board_build.flash_size = "16MB";
        board_upload.flash_size = "16MB";
        board = "freenove_esp32_s3_wroom";

        lib_deps = [
          # "moononournation/Arduino_GFX@1.4.7"
          "moononournation/GFX Library for Arduino@1.6.5"
        ];

        build_flags = [
          "-DBOARD_HAS_PSRAM"
          "-DARDUINO_USB_MODE=0"
          "-DARDUINO_USB_CDC_ON_BOOT=0"
        ];
      };

      walter = base // {
        board = "walter";
        # framework = [ "espidf" ];
        # platform = "espressif32@6.13.0";
        # board_build = {
        #   esp-idf.sdkconfig_path = "${config.platformio.src_dir}/sdkconfig.walter";
        #   cmake_extra_args = [ "-DSDKCONFIG_DEFAULTS=\"${config.platformio.src_dir}/sdkconfig.defaults\"" ];
        # };
      };

      base = {
        framework = "arduino";
        platform = "espressif32";
        board_build.filesystem = "littlefs";

        lib_ldf_mode = "chain";
        lib_compat_mode = "strict";

        build_src_filter = [
          "+<*>"
          "-<*.rs>"
          "-<.git/>"
          "-<.svn/>"
          "-<**/*.rs>"
        ];

        monitor_dtr = 0;
        monitor_rts = 0;
        monitor_echo = "yes";
        upload_speed = 921600;
        monitor_speed = 115200;
        monitor_filters = "direct";
        # monitor_port = "rfc2217://rpi5-16:2217?ign_set_control";
      };
    };
  };
}

# [env:uno]
# platform = atmelavr
# board = uno
# upload_speed = 115200

# [env:giga]
# platform = ststm32
# board = giga_r1_m7

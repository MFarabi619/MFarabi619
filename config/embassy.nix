{
  languages.rust.embassy = {
    enable = true;
    baud = 1500000;
    chip = "esp32s3";
    toolchain = "esp";
    after = "hard-reset";
    monitor_baud = 115200;
    before = "default-reset";
    port = "rfc2217://rpi5-16:2217?ign_set_control";

    cargo = {
      env.DEFMT_LOG = "info";
      build = {
        target = "xtensa-esp32s3-none-elf";
        rustflags = [
          "-C"
          "link-arg=-nostartfiles"
        ];
      };
      unstable."build-std" = [
        "alloc"
        "core"
      ];
    };
  };
}

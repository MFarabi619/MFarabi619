{
  # apple.sdk = null;
  # android = {
  #   enable = true;
  #   ndk.enable = true;
  #   emulator.enable = true;
  #   android-studio.enable = true;
  # };

  languages.rust = {
    enable = false; # set to false for firmware dev
    channel = "stable";
    targets = [
      # "i686-linux-android"
      # "x86_64-linux-android"
      # "aarch64-linux-android"
      # "aarch64-apple-ios-sim"
      "wasm32-unknown-unknown"
      # "armv7-linux-androideabi"
    ];

    components = [
      "rustc"
      "cargo"
      "clippy"
      "rustfmt"
      "rust-analyzer"
    ];
  };
}

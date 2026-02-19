{
  languages.rust = {
    enable = true;
    channel = "stable";
    loco.enable = true;
    embassy.enable = true;

    dioxus = {
      enable = true;
      desktop.linux.enable = false;
      mobile.android.enable = false;
    };

    components = [
      "rustc"
      "cargo"
      "clippy"
      "rustfmt"
      "rust-analyzer"
    ];
  };
}

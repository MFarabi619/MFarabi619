{
  languages.rust = {
    enable = true; # set to false for firmware dev
    channel = "stable";
    loco.enable = true;

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

{
  languages.rust = {
    enable = true; # set to false for firmware dev
    channel = "stable";
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

{
  ...
}:
{
  languages.rust = {
    enable = true;
    channel = "stable";
    # lld.enable = true;  # FIXME: breaks dioxus
    # mold.enable = true; # FIXME: breaks loco

    components = [
      "rustc"
      "cargo"
      "clippy"
      "rustfmt"
      "rust-std"
      "rust-src"
      "rust-analyzer"
    ];

    loco.enable = true;
    dioxus = {
      enable = true;
      desktop.linux.enable = false;
      mobile.android.enable = false;
    };
  };
}

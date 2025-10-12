# github.com/jtroo/kanata/releases/tag/v1.9.0
# github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/main
# github.com/jtroo/kanata/discussions/1537
{
  pkgs,
  ...
}:
{
  services.karabiner-elements = {
    enable = false;
    package = pkgs.karabiner-elements.overrideAttrs (old: {
      version = "14.13.0";

      src = pkgs.fetchurl {
        inherit (old.src) url;
        hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
      };

      dontFixup = true;
    });
  };
}

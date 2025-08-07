{
  pkgs,
  ...
}:
{
  programs.sketchybar = {
    enable = pkgs.stdenv.isDarwin;
    service.enable = true;
    includeSystemPath = true;
    config = {
      source = ./sketchybarrc;
      recursive = true;
    };
  };
}

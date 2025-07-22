{
  programs = {
    sketchybar = {
      enable = true;
      service.enable = true;
      includeSystemPath = true;
      config = {
        source = ./sketchybarrc;
        recursive = true;
      };
    };
  };
}

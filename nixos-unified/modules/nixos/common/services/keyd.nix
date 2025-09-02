{
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = ["*"];
        settings = {
          main = {
            capslock = "overload(control, esc)";
            rightalt = "layer(rightalt)";
          };
          rightalt = {
           h = "left";
           j = "down";
           k = "up";
           l = "right";
          };
        };
        extraConfig = ''
          [control+shift]
          h = left
        '';
      };
      # externalKeyboard = {
      #   ids = [ "1ea7:0907" ];
      #   settings = {
      #     main = {
      #       esc = capslock;
      #     };
      #   };
      # };
    };
  };
}

{
  config,
  ...
}:
{
  services.emacs = rec {
    defaultEditor = false;
    enable = config.programs.emacs.enable;
    # socketActivation.enable = true;
    # extraOptions = [ "TERM=xterm-kitty" ];

    client = {
      inherit enable;
      # arguments = [ "-nw" ];
    };
  };
}

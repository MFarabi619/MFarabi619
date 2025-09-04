{
  programs.less = {
    enable = true;
    # config = ''
    #   #command
    #     s        back-line
    #     t        forw-line
    #   '';
    options = {
       # RAW-CONTROL-CHARS = true;
       #  quiet = true;
       #  wheel-lines = 3;
      LESSHISTFILE = "/tmp/less-hist";
      };
    };
}

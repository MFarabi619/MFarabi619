{
  programs.tiny = {
    enable = true;
    settings = {
    servers = [
          {
            tls = true;
            port = 6697;
            addr = "irc.libera.chat";
            realname = "Mumtahin Farabi";
            nicks = [ "johndoe" ];
          }
        ];
      defaults = {
        nicks = [ "johndoe" ];
        realname = "Mumtahin Farabi";
        join = [];
        tls = true;
      };
    };
  };
}

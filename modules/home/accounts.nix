{
  pkgs,
  config,
  ...
}:
{
  accounts = {
    email = {
      maildirBasePath = "Maildir";

      accounts = {
        Gmail = {
          enable = true;
          primary = true;
          mu.enable = true;
          msmtp.enable = true;
          flavor = "gmail.com";
          neomutt.enable = true;
          smtp.host = "smtp.gmail.com";
          address = config.me.email;
          userName = config.me.email;
          realName = config.me.fullname;
          passwordCommand = "${pkgs.pass}/bin/pass Email/GmailApp";

          signature = {
            showSignature = "append";

            text = ''
              Warm regards,
              config.me.fullname
            '';
          };

          mbsync = {
            enable = true;
            create = "both";
            expunge = "both";
            patterns = [
              "*"
              "[Gmail]*"
            ]; # "[Gmail]/Sent Mail" ];
          };

          # imap={
          #  port = 993;
          #  tls.enable = true;
          #  host = "imap.gmail.com";
          # };
        };
      };
    };

    # calendar = {
    #  accounts = {
    #    mfarabi = {
    #      khal = {
    #        enable = true;
    #      };

    #      qcal.enable = true;
    #      };
    #    };
    # };

    # contact = {
    #  # basePath = "";
    #  accounts = {
    #   mfarabi = {
    #     khard.enable = false;

    #     local ={
    #      type = "filesystem";
    #     };

    #     remote = {
    #      userName = "mfarabi";
    #       url = "";
    #       type = "carddav"; # http google_contacts
    #     };
    #   };
    #  };
    # };

  };
}

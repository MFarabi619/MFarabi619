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
        personal = {
          primary = true;
          address = config.me.email;
          userName = config.me.email;
          realName = config.me.fullname;
          flavor = "gmail.com";
          passwordCommand = "${pkgs.pass}/bin/pass Email/GmailApp";

          signature = {
            showSignature = "append";
            text = ''
              Warm regards,
              ${config.me.fullname}
            '';
          };

          mu.enable = true;
          msmtp.enable = true;
          neomutt.enable = true;

          mbsync = {
            enable = true;
            create = "both";
            remove = "none";
            expunge = "both";
            patterns = [
              "*"
              "![Gmail]/All Mail"
              "![Gmail]/Important"
              "![Gmail]/Starred"
            ];
          };
        };

        apidaesystems = {
          address = "farabi@apidaesystems.ca";
          userName = "farabi@apidaesystems.ca";
          realName = config.me.fullname;
          flavor = "gmail.com";
          passwordCommand = "${pkgs.pass}/bin/pass Email/apidaesystems";

          signature = {
            showSignature = "append";
            text = ''
              Warm regards,
              ${config.me.fullname}
            '';
          };

          mu.enable = true;
          msmtp.enable = true;
          neomutt.enable = true;

          mbsync = {
            enable = true;
            create = "both";
            remove = "none";
            expunge = "both";
            patterns = [
              "*"
              "![Gmail]/All Mail"
              "![Gmail]/Important"
              "![Gmail]/Starred"
            ];
          };
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

{
  pkgs,
  config,
  ...
}:
{
  accounts = {
    email = {
      maildirBasePath = "Maildir";

      accounts = rec {
        personal = {
          primary = true;
          flavor = "gmail.com";
          address = config.me.email;
          userName = config.me.email;
          realName = config.me.fullname;
          passwordCommand = "${pkgs.pass}/bin/pass Email/GmailApp";
          gpg.signByDefault = true;
          gpg.key = "306B94DA2CE6198A";

          signature = {
            showSignature = "append";
            text = ''
              Warm regards,
              ${config.me.fullname}
            '';
          };

          folders = {
            inbox = "Inbox";
            trash = "[Gmail]/Trash";
            drafts = "[Gmail]/Drafts";
            sent = "[Gmail]/Sent Mail";
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

          imapnotify = {
            enable = true;
            boxes = [ "Inbox" ];
            onNotify = "${pkgs.isync}/bin/mbsync personal";
            onNotifyPost = "${pkgs.mu}/bin/mu index";
          };
        };

        apidaesystems = {
          gpg = personal.gpg;
          flavor = personal.flavor;
          folders = personal.folders;
          realName = config.me.fullname;

          address = "farabi@apidaesystems.ca";
          userName = "farabi@apidaesystems.ca";
          passwordCommand = "${pkgs.pass}/bin/pass Email/apidaesystems";

          mu.enable = true;
          msmtp.enable = true;
          neomutt.enable = true;
          mbsync = personal.mbsync;

          signature = {
            showSignature = "append";
            text = ''
              Warm regards,
              ${config.me.fullname}
            '';
          };

          imapnotify = {
            enable = true;
            boxes = [ "Inbox" ];
            onNotify = "${pkgs.isync}/bin/mbsync apidaesystems";
            onNotifyPost = "${pkgs.mu}/bin/mu index";
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

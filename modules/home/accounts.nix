{
  pkgs,
  config,
  ...
}:
let
  gmailCommon = {
    enable = true;
    mu.enable = true;
    msmtp.enable = true;
    flavor = "gmail.com";
    neomutt.enable = true;
    realName = config.me.fullname;

    signature = {
      showSignature = "append";
      text = ''
        Warm regards,
        ${config.me.fullname}
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
  };

  mkGmailAccount =
    {
      address,
      passwordCommand,
      primary ? false,
    }:
    gmailCommon
    // {
      inherit address passwordCommand primary;
      userName = address;
      smtp.host = "smtp.${gmailCommon.flavor}";
    };
in
{
  accounts = {
    email = {
      maildirBasePath = "Maildir";

      accounts = {
        Gmail = mkGmailAccount {
          address = config.me.email;
          passwordCommand = "${pkgs.pass}/bin/pass Email/GmailApp";
          primary = true;
        };

        "apidaesystems" = mkGmailAccount {
          address = "farabi@apidaesystems.ca";
          passwordCommand = "${pkgs.pass}/bin/pass Email/apidaesystems";
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

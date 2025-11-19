{
  accounts = {
    email = {
     maildirBasePath = "Maildir"; # default

     accounts = {
       Gmail = {
       enable = true;
       primary = true;
       mu.enable = true;
       msmtp.enable = true;
       flavor = "gmail.com";
       # passwordCommand = "pass gmail";
       realName = "Mumtahin Farabi";
       smtp.host = "smtp.gmail.com";
       address = "mfarabi619@gmail.com";
       userName = "mfarabi619@gmail.com";

       signature = {
         text = ''
         Warm regards,
         Mumtahin Farabi
         '';
         showSignature = "append";
       };

       mbsync = {
         enable = true;
         create = "both";
         expunge = "both";
         patterns = [ "*" "[Gmail]*" ]; # "[Gmail]/Sent Mail" ];
       };

       # imap={
       #  port = 993;
       #  tls.enable = true;
       #  host = "imap.gmail.com";
       # };

       # smtp = {
       #  port = 587;
       #   tls.useStartTls = true;
       #   host = "smtp.gmail.com";
       # };
      };
     };
    };

   calendar = {
    accounts = {
      mfarabi = {

     khal = {
      enable = true;
     };
        qcal.enable = true;
    };
      };
   };

    contact = {
     # basePath = "";
     accounts = {
      mfarabi = {
        khard.enable = false;

        local ={
         type = "filesystem";
        };

        remote = {
         userName = "mfarabi";
          url = "";
          type = "carddav"; # http google_contacts
        };
      };
     };
    };

  };
}

{
  accounts = {
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

    email = {
     maildirBasePath = "Maildir"; # default
     accounts = {
       "mfarabi" = {
       enable = true;
       realName = "Mumtahin Farabi";
       smtp.host = "smtp.gmail.com";
       imapnotify.enable = false;
       smtp.tls.enable = true;
       address = "mfarabi619@gmail.com";
       userName = "mfarabi619@gmail.com";

       imap={
        host = "imap.gmail.com";
        tls.enable = true;
       };

       mu.enable = true;
        getmail = {
          enable = false;
          delete = false;
          readAll = true;
      };
        offlineimap={
          enable = true;
          # postSyncHookCommand = "";
          # extraConfig = {
          #   account = {
          #     autrefresh = 20;
          #   };
          # };
          # local = {
          #   sync_deletes = true;
          # };
          # remote = {
          #   expunge = false;
          #   maxconnections = 2;
          # };
          };
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
  };
}

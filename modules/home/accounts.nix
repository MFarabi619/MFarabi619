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
     accounts = {
      mfarabi = {
       enable = true;
        mu.enable = true;
        aerc.enable = false;
        lieer.enable = false;
        msmtp.enable = false;
        mbsync.enable = false;
        mujmap.enable = false;
        astroid.enable = false;
        getmail = {
          enable = false;
          delete = false;
          readAll = true;
      };
        neomutt.enable = false;
        notmuch.enable  = false;
        himalaya.enable = false;
        offlineimap.enable = false;
       thunderbird = {
         enable = false;
         profiles = {
          accountsOrder = [];
          calendarAccountsOrder = [];
         };
      };
       # vdirsyncer = {
       #  enable = false;
       # };
        imap.tls.enable = true;
        imapnotify.enable = false;
        smtp.tls.enable = true;
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

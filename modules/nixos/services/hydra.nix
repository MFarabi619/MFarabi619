{
  # https://nixos.wiki/wiki/Hydra
  #  hydra-create-user mfarabi --full-name 'Mumtahin Farabi' --email-address 'mfarabi619@gmail.com' --password-prompt --role admin
  services.hydra = {
    enable = false;
    port = 3000;
    tracker = "";
    extraEnv = {};
    maxServers = 25;
    listenHost = "*";
    extraConfig = '''';
    debugServer = false;
    useSubstitutes = false;
    minimumDiskFree = 0;
    minSpareServers = 5;
    maxSpareServers = 5;
    smtpHost = "localhost";
    # buildMachinesFiles = [ ];
    minimumDiskFreeEvaluator = 0;
    hydraURL = "http:/localhost:9870";
    notificationSender = "hydra@localhost";
    dbi = "dbi:Pg:dbname=hydra;user=hydra;";
    gcRootsDir = "/nix/var/nix/gcroots/hydra";
    # logo = ./;
  };
}

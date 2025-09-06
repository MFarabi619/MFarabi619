{
  # https://nixos.wiki/wiki/Hydra
  #  hydra-create-user mfarabi --full-name 'Mumtahin Farabi' --email-address 'mfarabi619@gmail.com' --password-prompt --role admin
  services.hydra = {
    enable = false;
    hydraURL = "http:/localhost:9870";
    notificationSender = "hydra@localhost";
    buildMachinesFiles = [ ];
    useSubstitutes = true;
    # logo = ./;
  };
}

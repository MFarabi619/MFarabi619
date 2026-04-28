{
  flake,
  config,
  ...
}:
{
  imports = [
    flake.inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    defaultSopsFile = "${flake.self}/secrets.yaml";
    gnupg.home = "${config.home.homeDirectory}/.gnupg";

    secrets = {
      PULUMI_CONFIG_PASSPHRASE = {};
    };
  };
}

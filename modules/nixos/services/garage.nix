# sudo garage status
# sudo garage layout show
# sudo garage layout assign 32dcc7944c962756 --zone ottawa-east-1 --capacity 80000000000
# sudo garage layout apply --version 1
# sudo garage bucket create dokploy
# sudo garage key create dokploy
# sudo garage key list

# sudo rm -rf /var/lib/garage/meta/cluster_layout
{
  pkgs,
  config,
  ...
}:
{
  services.garage = {
    package = pkgs.garage_2;
    environmentFile = "/var/lib/secrets/garage";
    # enable = config.networking.hostName == "framework-desktop";

    settings = {
      replication_factor = 1;
      rpc_bind_addr = "0.0.0.0:3901";

      s3_api = {
        s3_region = "garage";
        api_bind_addr = "0.0.0.0:3900";
      };
    };
  };
}

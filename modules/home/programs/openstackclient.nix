{
  pkgs,...
}:
{
  # home.packages = with pkgs; [openstack-rs];
  programs.openstackclient = {
    enable = false;
    clouds = {
      # my-infra = {
      #   cloud = "example-cloud";
      #   auth = {
      #     project_id = "0123456789abcdef0123456789abcdef";
      #     username = "openstack";
      #   };
      #   region_name = "XXX";
      #   interface = "internal";
      # };
    };
    publicClouds = {
      # example-cloud = {
      #   auth = {
      #     auth_url = "https://identity.cloud.example.com/v2.0";
      #   };
      # };
    };
  };
}

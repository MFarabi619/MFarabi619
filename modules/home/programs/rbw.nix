{
  config,
  ...
}:
{
  programs.rbw = {
    enable = false;
    settings = {
      email = config.me.email;
      # base_url = "";
      # identity_url = "";
    };
  };
}

{
  pkgs,
  config,
  ...
}:
{
  security.acme = {
    acceptTerms = true;

    defaults = {
      email = "mfarabi619@gmail.com";
    };

    certs = {
      "openws.org" = {
        domain = "openws.org";
        dnsProvider = "cloudflare";
        dnsPropagationCheck = true;
        dnsResolver = "1.1.1.1:53";
        extraDomainNames = [ "*.openws.org" ];
        # group = config.services.caddy.group;
        environmentFile = "/etc/cloudflared/.env";
      };
    };
  };
}

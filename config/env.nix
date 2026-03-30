let
  URLS = {
    BASE = "https://mfarabi.sh";
    EXERCISM = "https://api.exercism.org/v1";
  };
in
{

  env = rec {
    BASE_URL = URLS.BASE;
    ZELLIJ_AUTO_EXIT = "true";
    ZELLIJ_AUTO_ATTACH = "true";
    # PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    # PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";
  };
}

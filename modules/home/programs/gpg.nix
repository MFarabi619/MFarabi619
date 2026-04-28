{
  programs.gpg = {
    enable = true;
    mutableKeys = true;
    mutableTrust = true;

    settings = {
      use-agent = true;
      no-comments = true;
      keyid-format = "long";
      no-emit-version = true;
      with-fingerprint = true;
      default-key = "306B94DA2CE6198A";
    };

    publicKeys = [
      {
        trust = "ultimate";
        source = ../gpg-public.asc;
      }
    ];
  };
}

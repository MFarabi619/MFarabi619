{
  services.glance = {
    enable = true;
    settings = {
      pages = [
        {
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "calendar";
                }
              ];
            }
          ];
          name = "Calendar";
        }
      ];
    };
  };
}

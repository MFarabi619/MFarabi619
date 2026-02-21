{
  lib,
  pkgs,
  config,
  ...
}:

let
  loco = config.languages.rust.loco;

  default_config_folder =
    if config ? git && config.git ? root then "${config.git.root}/config" else "./config";
  final_config_folder = lib.defaultTo default_config_folder loco.env.LOCO_CONFIG_FOLDER;
  development_yaml = lib.recursiveUpdate loco.config.development loco.config.extra_config;

in
{
  options.languages.rust.loco = {
    enable = lib.mkEnableOption "Loco.rs development tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.loco;
      defaultText = lib.literalExpression "pkgs.loco";
    };

    writeConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    env = lib.mkOption {
      type = lib.types.submodule {
        options = {
          LOCO_CONFIG_FOLDER = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Defaults to `${default_config_folder}`.";
          };

          LOCO_ENV = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          NODE_ENV = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          LOCO_DATA = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          RAILS_ENV = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          SCHEDULER_CONFIG = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          LOCO_POSTGRES_DB_OPTIONS = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      };
      default = { };
    };

    config = lib.mkOption {
      type = lib.types.submodule {
        options = {
          development = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                workers.mode = lib.mkOption {
                  type = lib.types.enum [
                    "BackgroundQueue"
                    "ForegroundBlocking"
                    "BackgroundAsync"
                  ];
                  default = "BackgroundAsync";
                };

                logger = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      enable = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                      level = lib.mkOption {
                        type = lib.types.enum [
                          "trace"
                          "debug"
                          "info"
                          "warn"
                          "error"
                        ];
                        default = "debug";
                      };
                      format = lib.mkOption {
                        type = lib.types.enum [
                          "compact"
                          "pretty"
                          "json"
                        ];
                        default = "compact";
                      };
                      pretty_backtrace = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                    };
                  };
                };

                server = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      port = lib.mkOption {
                        type = lib.types.port;
                        default = 5150;
                      };
                      binding = lib.mkOption {
                        type = lib.types.str;
                        default = "localhost";
                      };
                      host = lib.mkOption {
                        type = lib.types.str;
                        default = "http://localhost";
                      };

                      middlewares = lib.mkOption {
                        default = { };
                        type = lib.types.submodule {
                          options = {
                            fallback.enable = lib.mkOption {
                              type = lib.types.bool;
                              default = false;
                            };

                            static = lib.mkOption {
                              default = { };
                              type = lib.types.submodule {
                                options = {
                                  enable = lib.mkOption {
                                    type = lib.types.bool;
                                    default = true;
                                  };
                                  must_exist = lib.mkOption {
                                    type = lib.types.bool;
                                    default = true;
                                  };
                                  precompressed = lib.mkOption {
                                    type = lib.types.bool;
                                    default = false;
                                  };
                                  fallback = lib.mkOption {
                                    type = lib.types.str;
                                    default = "assets/static/404.html";
                                  };

                                  folder.uri = lib.mkOption {
                                    type = lib.types.str;
                                    default = "/static";
                                  };
                                  folder.path = lib.mkOption {
                                    type = lib.types.str;
                                    default = "assets/static";
                                  };
                                };
                              };
                            };
                          };
                        };
                      };
                    };
                  };
                };

                mailer.smtp = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      port = lib.mkOption {
                        type = lib.types.port;
                        default = 1025;
                      };
                      enable = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                      secure = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                      };
                      host = lib.mkOption {
                        type = lib.types.str;
                        default = "localhost";
                      };
                    };
                  };
                };

                database = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      idle_timeout = lib.mkOption {
                        type = lib.types.ints.positive;
                        default = 500;
                      };
                      auto_migrate = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                      min_connections = lib.mkOption {
                        type = lib.types.ints.positive;
                        default = 1;
                      };
                      max_connections = lib.mkOption {
                        type = lib.types.ints.positive;
                        default = 1;
                      };
                      enable_logging = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                      };
                      connect_timeout = lib.mkOption {
                        type = lib.types.ints.positive;
                        default = 500;
                      };
                      dangerously_truncate = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                      };
                      dangerously_recreate = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                      };
                      uri = lib.mkOption {
                        type = lib.types.str;
                        default = "sqlite://api_development.sqlite?mode=rwc";
                      };
                    };
                  };
                };

                auth.jwt = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      expiration = lib.mkOption {
                        type = lib.types.ints.positive;
                        default = 604800;
                      };
                      secret = lib.mkOption {
                        type = lib.types.str;
                        default = "EuMvNwuLnnaAgt3Jx7lw";
                      };
                    };
                  };
                };
              };
            };
          };

          extra_config = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "Deep-merged into development.yaml after typed config.";
          };
        };
      };
      default = { };
    };
  };

  config = lib.mkIf loco.enable {
    assertions = [
      {
        assertion = (!loco.writeConfig) || final_config_folder != null;
        message = "languages.rust.loco.writeConfig is true, but LOCO_CONFIG_FOLDER resolved to null.";
      }
    ];

    env = {
      LOCO_CONFIG_FOLDER = final_config_folder;
    }
    // lib.optionalAttrs (loco.env.LOCO_ENV != null) { LOCO_ENV = loco.env.LOCO_ENV; }
    // lib.optionalAttrs (loco.env.NODE_ENV != null) { NODE_ENV = loco.env.NODE_ENV; }
    // lib.optionalAttrs (loco.env.LOCO_DATA != null) { LOCO_DATA = loco.env.LOCO_DATA; }
    // lib.optionalAttrs (loco.env.RAILS_ENV != null) { RAILS_ENV = loco.env.RAILS_ENV; }
    // lib.optionalAttrs (loco.env.SCHEDULER_CONFIG != null) {
      SCHEDULER_CONFIG = loco.env.SCHEDULER_CONFIG;
    }
    // lib.optionalAttrs (loco.env.LOCO_POSTGRES_DB_OPTIONS != null) {
      LOCO_POSTGRES_DB_OPTIONS = loco.env.LOCO_POSTGRES_DB_OPTIONS;
    };

    files = lib.mkIf loco.writeConfig {
      "${final_config_folder}/development.yaml".yaml = development_yaml;
    };

    packages = [
      loco.package
      pkgs.sea-orm-cli
    ];
  };
}

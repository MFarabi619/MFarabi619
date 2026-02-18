{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.languages.rust.loco = {
    enable = lib.mkEnableOption "Loco.rs development tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.loco;
      defaultText = lib.literalExpression "pkgs.loco";
      description = "The loco CLI package to use.";
    };

    env = {
      LOCO_ENV = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Application environment (development, production, etc.).";
      };

      LOCO_CONFIG_FOLDER = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to configuration folder.";
      };

      LOCO_DATA = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Loco data directory.";
      };

      SCHEDULER_CONFIG = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Scheduler configuration path or file.";
      };

      LOCO_POSTGRES_DB_OPTIONS = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PostgreSQL connection options string.";
      };

      RAILS_ENV = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Rails-compatible environment value.";
      };

      NODE_ENV = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Node environment value.";
      };
    };
  };

  config = lib.mkIf config.languages.rust.loco.enable {
    languages.rust.enable = lib.mkDefault true;

    packages = [
      config.languages.rust.loco.package
      pkgs.sea-orm-cli
    ];

    env = lib.mkMerge [
      (lib.mkIf (config.languages.rust.loco.env.LOCO_POSTGRES_DB_OPTIONS != null) {
        LOCO_POSTGRES_DB_OPTIONS = config.languages.rust.loco.env.LOCO_POSTGRES_DB_OPTIONS;
      })

      (lib.mkIf (config.languages.rust.loco.env.LOCO_ENV != null) {
        LOCO_ENV = config.languages.rust.loco.env.LOCO_ENV;
      })

      (lib.mkIf (config.languages.rust.loco.env.RAILS_ENV != null) {
        RAILS_ENV = config.languages.rust.loco.env.RAILS_ENV;
      })

      (lib.mkIf (config.languages.rust.loco.env.NODE_ENV != null) {
        NODE_ENV = config.languages.rust.loco.env.NODE_ENV;
      })

      (lib.mkIf (config.languages.rust.loco.env.LOCO_CONFIG_FOLDER != null) {
        LOCO_CONFIG_FOLDER = config.languages.rust.loco.env.LOCO_CONFIG_FOLDER;
      })

      (lib.mkIf (config.languages.rust.loco.env.SCHEDULER_CONFIG != null) {
        SCHEDULER_CONFIG = config.languages.rust.loco.env.SCHEDULER_CONFIG;
      })

      (lib.mkIf (config.languages.rust.loco.env.LOCO_DATA != null) {
        LOCO_DATA = config.languages.rust.loco.env.LOCO_DATA;
      })
    ];
  };
}

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
in
{
  options.languages.rust.loco = {
    enable = lib.mkEnableOption "Loco.rs development tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.loco;
      defaultText = lib.literalExpression "pkgs.loco";
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
  };

  config = lib.mkIf loco.enable {
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

    packages = [
      loco.package
      pkgs.sea-orm-cli
    ];
  };
}

{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.platformio;
  types = lib.types;
  ini_path = "${config.git.root}/platformio.ini";

  mk_nullable_string =
    description:
    lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      inherit description;
    };

  mk_nullable_int =
    description:
    lib.mkOption {
      type = types.nullOr types.int;
      default = null;
      inherit description;
    };

  mk_nullable_positive_int =
    description:
    lib.mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      inherit description;
    };

  mk_nullable_string_list =
    description:
    lib.mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      inherit description;
    };

  mk_nullable_string_or_string_list =
    description:
    lib.mkOption {
      type = types.nullOr (
        types.oneOf [
          types.str
          (types.listOf types.str)
        ]
      );
      default = null;
      inherit description;
    };

  mk_option_from_constructor =
    constructor: description:
    {
      nullable_string = mk_nullable_string;
      nullable_int = mk_nullable_int;
      nullable_positive_int = mk_nullable_positive_int;
      nullable_string_list = mk_nullable_string_list;
      nullable_string_or_string_list = mk_nullable_string_or_string_list;
    }
    .${constructor}
      description;

  mk_options_from_specs =
    specs: lib.mapAttrs (_: spec: mk_option_from_constructor spec.constructor spec.description) specs;

  env_common_option_specs = {
    framework = {
      constructor = "nullable_string_or_string_list";
      description = "Framework name for this environment.";
    };
    build_flags = {
      constructor = "nullable_string_list";
      description = "Build flags rendered into [env*] build_flags.";
    };
    build_src_flags = {
      constructor = "nullable_string_list";
      description = "Source build flags rendered into [env*] build_src_flags.";
    };
    build_src_filter = {
      constructor = "nullable_string_list";
      description = "This option allows one to specify which source files should be included or excluded from src_dir for a build process.";
    };
    board = {
      constructor = "nullable_string";
      description = "Board name for this environment.";
    };
    platform = {
      constructor = "nullable_string";
      description = "Platform name for this environment.";
    };
    targets = {
      constructor = "nullable_string_list";
      description = "Targets to render into [env*] targets.";
    };
    upload_port = {
      constructor = "nullable_string";
      description = "Upload port string (e.g. rfc2217://host:2217?ign_set_control).";
    };
    upload_speed = {
      constructor = "nullable_positive_int";
      description = "Upload baud rate.";
    };
    upload_protocol = {
      constructor = "nullable_string";
      description = "A protocol that “uploader” tool uses to talk to a board. Please check Boards for supported uploading protocols by your board.";
    };
    upload_command = {
      constructor = "nullable_string";
      description = ''
        Override default Development Platforms upload command with a custom command.

        In order to use upload_command, upload_protocol = custom must be specified.
      '';
    };
    monitor_rts = {
      constructor = "nullable_int";
      description = "Monitor RTS value.";
    };
    monitor_dtr = {
      constructor = "nullable_int";
      description = "Monitor DTR value.";
    };
    monitor_echo = {
      constructor = "nullable_string";
      description = "Monitor echo setting.";
    };
    monitor_port = {
      constructor = "nullable_string";
      description = "Optional monitor port. Falls back to upload_port.";
    };
    monitor_speed = {
      constructor = "nullable_positive_int";
      description = "Monitor baud rate.";
    };
    monitor_filters = {
      constructor = "nullable_string";
      description = "Monitor filter string.";
    };
    test_port = {
      constructor = "nullable_string";
      description = "Optional test port. Falls back to upload_port.";
    };
    test_speed = {
      constructor = "nullable_positive_int";
      description = "Optional test speed. Falls back to monitor_speed.";
    };
    lib_ldf_mode = {
      constructor = "nullable_string";
      description = "LDF mode for this environment.";
    };
    lib_compat_mode = {
      constructor = "nullable_string";
      description = "LDF compatibility mode for this environment.";
    };
    check_src_filters = {
      constructor = "nullable_string_list";
      description = "check_src_filters list.";
    };
    check_flags = {
      constructor = "nullable_string_list";
      description = "check_flags list.";
    };
  };

  env_common_options = mk_options_from_specs env_common_option_specs;

  join_or_null =
    values: if values == null || values == [ ] then null else lib.concatStringsSep ", " values;

  csv_or_null =
    value:
    if value == null then
      null
    else if lib.isList value then
      join_or_null value
    else
      value;

  render_multiline_indented_or_null =
    values:
    if values == null || values == [ ] then null else "\n  ${lib.concatStringsSep "\n  " values}";

  remove_nulls =
    value:
    if lib.isAttrs value then
      lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: remove_nulls v) value)
    else if lib.isList value then
      map remove_nulls value
    else
      value;

  script_file_name =
    script_name: if lib.hasSuffix ".py" script_name then script_name else "${script_name}.py";

  script_ref = phase: script: "${phase}:${script_file_name script.name}";

  script_path =
    script:
    if script.shared_with_remote then
      "${cfg.shared_dir}/${script_file_name script.name}"
    else
      "${config.git.root}/${script_file_name script.name}";

  extra_scripts_type = types.submodule {
    options = {
      text = lib.mkOption {
        type = types.lines;
        default = "";
        description = "Python script source.";
      };

      pre = lib.mkOption {
        type = types.bool;
        default = true;
        description = "If true, render as pre:<name>.py; otherwise as <name>.py.";
      };

      name = lib.mkOption {
        type = types.str;
        default = "extra_scripts";
        description = "Script filename (without .py suffix is allowed).";
      };

      shared_with_remote = lib.mkOption {
        type = types.bool;
        default = false;
        description = "If true, place script under platformio.shared_dir; otherwise in repo root.";
      };
    };
  };

  normalize_extra_scripts =
    extra_scripts:
    if extra_scripts.text == "" then
      [ ]
    else
      [
        {
          name = extra_scripts.name;
          text = extra_scripts.text;
          shared_with_remote = extra_scripts.shared_with_remote;
          phase = if extra_scripts.pre then "pre" else null;
        }
      ];

  script_refs =
    extra_scripts:
    map (
      script:
      if script.phase == null then script_file_name script.name else script_ref script.phase script
    ) (normalize_extra_scripts extra_scripts);

  mk_env_section =
    env_cfg:
    remove_nulls (
      {
        board = env_cfg.board;
        extends = env_cfg.extends;
        platform = env_cfg.platform;
        framework = csv_or_null env_cfg.framework;

        build_flags = render_multiline_indented_or_null env_cfg.build_flags;
        build_src_flags = render_multiline_indented_or_null env_cfg.build_src_flags;
        build_src_filter = render_multiline_indented_or_null env_cfg.build_src_filter;

        targets = join_or_null env_cfg.targets;
        extra_scripts = join_or_null (script_refs env_cfg.extra_scripts);

        upload_port = env_cfg.upload_port;
        upload_speed = env_cfg.upload_speed;
        upload_command = env_cfg.upload_command;
        upload_protocol = env_cfg.upload_protocol;

        monitor_rts = env_cfg.monitor_rts;
        monitor_dtr = env_cfg.monitor_dtr;
        monitor_echo = env_cfg.monitor_echo;
        monitor_port = if env_cfg.monitor_port == null then env_cfg.upload_port else env_cfg.monitor_port;
        monitor_speed = env_cfg.monitor_speed;
        monitor_filters = env_cfg.monitor_filters;

        test_port = if env_cfg.test_port == null then env_cfg.upload_port else env_cfg.test_port;
        test_speed = if env_cfg.test_speed == null then env_cfg.monitor_speed else env_cfg.test_speed;

        lib_ldf_mode = env_cfg.lib_ldf_mode;
        lib_compat_mode = env_cfg.lib_compat_mode;
        lib_deps = join_or_null env_cfg.lib_deps;

        check_src_filters = join_or_null env_cfg.check_src_filters;
        check_flags = join_or_null env_cfg.check_flags;

        "board_build.filesystem" = env_cfg.board_build.filesystem;
        "board_build.flash_size" = env_cfg.board_build.flash_size;
        "board_upload.flash_size" = env_cfg.board_upload.flash_size;
        "board_build.esp-idf.sdkconfig_path" = env_cfg.board_build.esp-idf.sdkconfig_path;
        "board_build.cmake_extra_args" =
          render_multiline_indented_or_null env_cfg.board_build.cmake_extra_args;
      }
      // env_cfg.extra_options
    );

  mk_env_options = {
    extends = mk_nullable_string "Base environment to extend.";
  }
  // env_common_options
  // {
    extra_scripts = lib.mkOption {
      type = extra_scripts_type;
      default = { };
      description = "Extra script config rendered to platformio.ini extra_scripts.";
    };
    lib_deps = mk_nullable_string_list "List of libraries for lib_deps.";

    board_build.filesystem = mk_nullable_string "board_build.filesystem (e.g. littlefs).";
    board_build.flash_size = mk_nullable_string "board_build.flash_size \"8MB\".";
    board_upload.flash_size = mk_nullable_string "board_upload.flash_size \"8MB\".";
    board_build.esp-idf.sdkconfig_path = mk_nullable_string "board_build.esp-idf.sdkconfig_path (custom ESP-IDF sdkconfig file path).";
    board_build.cmake_extra_args = mk_nullable_string_list "board_build.cmake_extra_args list.";

    extra_options = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Extra [env*] keys (passthrough).";
    };
  };

  env_submodule_type = types.submodule { options = mk_env_options; };

  base_env_cfg = {
    board = cfg.board;
    extends = null;
    platform = cfg.platform;
    framework = cfg.framework;
    build_flags = cfg.build_flags;
    build_src_flags = cfg.build_src_flags;
    build_src_filter = cfg.build_src_filter;

    targets = cfg.targets;
    extra_scripts = cfg.extra_scripts;

    upload_port = cfg.upload_port;
    upload_speed = cfg.upload_speed;
    upload_command = cfg.upload_command;
    upload_protocol = cfg.upload_protocol;

    monitor_rts = cfg.monitor_rts;
    monitor_dtr = cfg.monitor_dtr;
    monitor_echo = cfg.monitor_echo;
    monitor_port = cfg.monitor_port;
    monitor_speed = cfg.monitor_speed;
    monitor_filters = cfg.monitor_filters;

    test_port = cfg.test_port;
    test_speed = if cfg.test_speed == null then cfg.monitor_speed else cfg.test_speed;

    lib_ldf_mode = cfg.lib_ldf_mode;
    lib_compat_mode = cfg.lib_compat_mode;
    lib_deps = cfg.lib_deps;

    check_src_filters = cfg.check_src_filters;
    check_flags = cfg.check_flags;

    board_build.filesystem = cfg.board_build.filesystem;
    board_build.flash_size = cfg.board_build.flash_size;
    board_upload.flash_size = cfg.board_upload.flash_size;
    board_build.esp-idf.sdkconfig_path = cfg.board_build.esp-idf.sdkconfig_path;
    board_build.cmake_extra_args = cfg.board_build.cmake_extra_args;
    extra_options = cfg.env_extra_options;
  };

  env_extra_script_files =
    env_cfg:
    lib.listToAttrs (
      map (script: lib.nameValuePair (script_path script) { text = script.text; }) (
        normalize_extra_scripts env_cfg.extra_scripts
      )
    );

  generated_extra_script_files = lib.foldl' lib.recursiveUpdate { } (
    map env_extra_script_files ([ base_env_cfg ] ++ lib.attrValues cfg.envs)
  );

  has_empty_custom_extra_scripts =
    env_cfg:
    env_cfg.extra_scripts.text == ""
    && (
      env_cfg.extra_scripts.pre != true
      || env_cfg.extra_scripts.name != "extra_scripts"
      || env_cfg.extra_scripts.shared_with_remote
    );

  extra_script_assertions =
    let
      mk_assertion = section_name: env_cfg: {
        assertion = !has_empty_custom_extra_scripts env_cfg;
        message = "${section_name} sets extra_scripts options but extra_scripts.text is empty. Add text or remove extra_scripts overrides.";
      };
    in
    [ (mk_assertion "platformio ([env])" base_env_cfg) ]
    ++ lib.mapAttrsToList (
      env_name: env_cfg: mk_assertion "platformio.envs.${env_name} ([env:${env_name}])" env_cfg
    ) cfg.envs;

  platformio_section = remove_nulls (
    {
      default_envs = if cfg.default_envs == [ ] then null else lib.concatStringsSep ", " cfg.default_envs;

      name = cfg.name;
      lib_dir = cfg.lib_dir;
      src_dir = cfg.src_dir;
      data_dir = cfg.data_dir;
      test_dir = cfg.test_dir;
      boards_dir = cfg.boards_dir;
      shared_dir = cfg.shared_dir;
    }
    // cfg.extra_options
  );

  ini_sections = {
    platformio = platformio_section;
    env = mk_env_section base_env_cfg;
  }
  // lib.mapAttrs' (name: env_cfg: lib.nameValuePair "env:${name}" (mk_env_section env_cfg)) cfg.envs;

in
{
  options.platformio = {
    enable = lib.mkEnableOption "PlatformIO Development Tooling for Embedded Systems.";

    lib_deps = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Convenience list of common lib_deps you can reuse when composing
        platformio.lib_deps and platformio.envs.*.lib_deps.
      '';
    };

    default_envs = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of PlatformIO environments processed by default.
        Rendered to platformio.ini as a comma-separated string.
      '';
    };

    name = mk_nullable_string "Optional project name (platformio.ini [platformio] name).";

    src_dir = lib.mkOption {
      type = types.str;
      default = "src";
      description = "Path to the source directory (platformio.ini [platformio] src_dir).";
    };

    data_dir = lib.mkOption {
      type = types.str;
      default = "${config.platformio.src_dir}/../data";
      description = "Path to the data directory (platformio.ini [platformio] data_dir).";
    };

    test_dir = lib.mkOption {
      type = types.str;
      default = "${config.platformio.src_dir}/../test";
      description = "Path to the test directory (platformio.ini [platformio] test_dir).";
    };

    lib_dir = lib.mkOption {
      type = types.str;
      default = "${config.git.root}/libs";
      description = "Library directory (platformio.ini [platformio] lib_dir).";
    };

    boards_dir = lib.mkOption {
      type = types.str;
      default = "${config.git.root}/boards";
      description = "Boards directory (platformio.ini [platformio] boards_dir).";
    };

    shared_dir = lib.mkOption {
      type = types.str;
      default = "${config.git.root}/shared";
      description = "Shared directory (platformio.ini [platformio] shared_dir).";
    };

    extra_options = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Extra [platformio] keys (passthrough). Merged into the generated INI.";
    };

    # Base [env] options
    framework = env_common_options.framework;
    build_flags = env_common_options.build_flags;
    build_src_flags = env_common_options.build_src_flags;
    build_src_filter = env_common_options.build_src_filter;
    board = env_common_options.board;
    platform = env_common_options.platform;
    targets = env_common_options.targets;

    extra_scripts = lib.mkOption {
      type = extra_scripts_type;
      default = { };
      description = "Extra script config rendered to platformio.ini extra_scripts.";
    };

    upload_port = env_common_options.upload_port;
    upload_speed = env_common_options.upload_speed;
    upload_command = env_common_options.upload_command;
    upload_protocol = env_common_options.upload_protocol;

    monitor_rts = env_common_options.monitor_rts;
    monitor_dtr = env_common_options.monitor_dtr;
    monitor_echo = env_common_options.monitor_echo;
    monitor_port = env_common_options.monitor_port;
    monitor_speed = env_common_options.monitor_speed;
    monitor_filters = env_common_options.monitor_filters;

    test_port = env_common_options.test_port;
    test_speed = env_common_options.test_speed;

    lib_ldf_mode = env_common_options.lib_ldf_mode;
    lib_compat_mode = env_common_options.lib_compat_mode;

    check_src_filters = env_common_options.check_src_filters;
    check_flags = env_common_options.check_flags;

    board_build.filesystem = mk_nullable_string "board_build.filesystem (e.g. littlefs).";
    board_build.flash_size = mk_nullable_string "board_build.flash_size \"8MB\".";
    board_upload.flash_size = mk_nullable_string "board_upload.flash_size \"8MB\".";
    board_build.esp-idf.sdkconfig_path = mk_nullable_string "board_build.esp-idf.sdkconfig_path (custom ESP-IDF sdkconfig file path).";
    board_build.cmake_extra_args = mk_nullable_string_list "board_build.cmake_extra_args list.";

    env_extra_options = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Extra [env] keys (passthrough).";
    };

    envs = lib.mkOption {
      type = types.attrsOf env_submodule_type;
      default = { };
      description = "Named environments rendered to [env:<name>] sections in platformio.ini.";
    };

    boards = lib.mkOption {
      type = types.attrs;
      default = { };
      description = "Board definitions rendered to platformio.boards_dir/<name>.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = extra_script_assertions;

    packages =
      (with pkgs; [
        ninja
        ccache
        openocd
        esptool
      ])
      ++ lib.optionals pkgs.stdenv.isDarwin (
        with pkgs;
        [
          dfu-util
          kconfig-frontends
          python314Packages.kconfiglib
        ]
      );

    files = {
      "${ini_path}".ini = ini_sections;
    }
    // lib.mapAttrs' (
      board_name: board_config:
      lib.nameValuePair "${cfg.boards_dir}/${board_name}.json" {
        json = board_config // {
          name = board_config.name or board_name;
        };
      }
    ) cfg.boards
    // generated_extra_script_files;

    enterShell = lib.mkAfter ''
      echo -e "\033[36m[devenv:platformio]:\033[0m\033[32m Platformio workspace ready 🟧\033[0m"
    '';
  };
}

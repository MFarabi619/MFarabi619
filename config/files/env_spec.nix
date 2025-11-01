let
  VERSIONS = rec {
    NIX = "nix (Lix, like Nix) 2.94.0";
    DEVENV = "1.10.0";
    PNPM = "10.17.0";
    NODE_JS = "24.8.0";
  };
in
{
  files = {
    "tests/env_spec.sh" = {
      executable = true;
      text = ''
        # nix upgrade-nix
        Describe "❄ Nix should be:"
          It "using Lix implementation"
            When run nix --version
            The status should be success
            The line 1 should include "${VERSIONS.NIX}"
          End
        End

        # nix profile upgrade devenv --accept-flake-config
        # or
        # nix upgrade-nix
        Describe "🟦 Devenv should be:"
          It "greater than or equal to version ${VERSIONS.DEVENV}"
            When run devenv
            The status should be success
            The output should include '${VERSIONS.DEVENV}'
          End
        End

        Describe "📦 Pnpm should be:"
          It "installed via standalone script only"
            When run which pnpm
            The status should be success
            The line 3 should be undefined
          End

          It "greater than or equal to version ${VERSIONS.DEVENV}"
            When run pnpm --version
            The status should be success
            The output should include '${VERSIONS.PNPM}'
          End
        End

        Describe "🟢 Node.js should be:"
          It "greater than or equal to version ${VERSIONS.NODE_JS}"
            When run which node
            The status should be success
            The output should include 'nodejs-24.8'
            The output should end with '/bin/node'
          End
        End

        Describe "🔑 Secrets should be defined and present:"
          Parameters
            "DATABASE_URI"
          End

          Example "''${1}"
            The value "''${1}" should be defined
            The value "''${1}" should be present
          End
        End

        Describe "🖥 The Environment Variables should be defined as:"
          Parameters
            "NODE_ENV" ""
            "NX_VERBOSE_LOGGING" true
          End

          Example "''${1}=$2"
            The value "''${!1}" should be defined
            The value "''${!1}" should equal "$2"
          End
        End

        Describe "🐚 Ports should be defined and not conflict:"
          Skip if "Running Inside Zellij Session" [ "$(echo $ZELLIJ)" = "0" ]

          Parameters
            "API_SERVER_PORT" "5150"
            "APP_DEV_SERVER_PORT" "3000"
            "ADMIN_DEV_SERVER_PORT" "8000"
            "DOCS_DEV_SERVER_PORT" "4000"
            "GRAPH_DEV_SERVER_PORT" "4211"
            "NODE_MODULES_INSPECTOR_PORT" "7000"
            "ARCHITECTURE_DEV_SERVER_PORT" "5173"
          End

          Example "''${1}=''${2}"
            When run nc -zv localhost ''${!1}
            The status should be failure
            The error should include 'Connection refused'
          End
        End

        Describe "💿🟩 If Supabase is enabled:"
          Skip if "Supabase disabled" [ "$SUPABASE" != "true" ]

          Describe "🐳 Docker"
            It "socket should be activated"
              When run docker info
              The status should be success
              The output should not include 'ERROR'
            End

          Describe "container ports should not conflict:"
            Skip if "Running Inside Zellij Session" [ "$(echo $ZELLIJ)" = "0" ]

            Parameters
              "API" "54321"
              "GraphQL" "54321"
              "S3 Storage" "54321"
              "DB" "54322"
              "Studio" "54323"
              "Inbucket" "54324"
            End

            Example "$1=''${2}"
              When run nc -zv localhost ''${2}
              The status should be failure
              The error should include 'Connection refused'
            End
          End
          End
        End
      '';
    };
  };
}

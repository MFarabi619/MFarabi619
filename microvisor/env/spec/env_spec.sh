Describe "📦 Pnpm should be:"
It "installed via standalone script only"
When run which pnpm
The status should be success
The line 3 should be undefined
End

It "greater than or equal to version 10.10.0"
When run pnpm --version
The status should be success
The output should include '10.10'
End
End

Describe "🟢 Node.js should be:"
It "greater than or equal to version 22.14.0"
When run which node
The status should be success
The output should include 'nodejs-22.14'
The output should end with '/bin/node'
End
End

Describe "🔑 Secrets should be defined and present:"
Parameters
"DATABASE_URI"
"PAYLOAD_SECRET"
End

Example "${1}"
The value "${1}" should be defined
The value "${1}" should be present
End
End

Describe "🖥 The Environment Variables should be defined as:"
Parameters
# "DATABASE_URI" "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
"NX_VERBOSE_LOGGING" true
"NEXT_PUBLIC_ENABLE_AUTOLOGIN" "true"
End

Example "${1}=$2"
The value "${!1}" should be defined
The value "${!1}" should equal "$2"
End
End

Describe "🐚 Ports should be defined and not conflict:"
Skip if "Running Inside Zellij Session" [ "$(echo $ZELLIJ)" = "0" ]

Parameters
"APP_DEV_SERVER_PORT" "3000"
"ADMIN_DEV_SERVER_PORT" "8000"
"UI_SERVER_PORT" "6006"
"DOCS_DEV_SERVER_PORT" "4000"
"ARCHITECTURE_DEV_SERVER_PORT" "5173"
"GRAPH_DEV_SERVER_PORT" "4211"
"NODE_MODULES_INSPECTOR_PORT" "7000"
End

Example "${1}=${2}"
When run nc -zv localhost ${!1}
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

Example "$1=${2}"
When run nc -zv localhost ${2}
The status should be failure
The error should include 'Connection refused'
End

End

End

End

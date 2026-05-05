package main

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type voiceConfig struct {
	IsEnabled    bool   `json:"enabled"`
	OllamaURL    string `json:"ollamaURL"`
	OllamaModel  string `json:"ollamaModel"`
	PiperVoice   string `json:"piperVoice"`
	WhisperModel string `json:"whisperModel"`
	PipelineName string `json:"pipelineName"`
}

const voicePipelineScript = `#!/bin/sh
set -eu
RUN_CURL="docker run --rm --network=proxy curlimages/curl:8.10.0"

ready=0
for attempt in $(seq 1 60); do
    status=$($RUN_CURL -sf -o /dev/null -w "%{http_code}" http://home-assistant:8123/manifest.json 2>/dev/null || echo 000)
    case "$status" in 200) ready=1; break;; esac
    sleep 2
done
if [ "$ready" != "1" ]; then
    echo "home-assistant did not respond within 120s" >&2
    exit 1
fi

ready=0
for attempt in $(seq 1 60); do
    onboarding=$($RUN_CURL -s http://home-assistant:8123/api/onboarding 2>/dev/null || echo "")
    if echo "$onboarding" | grep -q '"step":"user"[^}]*"done":true'; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" != "1" ]; then
    echo "home-assistant onboarding did not complete within 120s" >&2
    exit 1
fi

docker exec -i \
    -e USERNAME="$USERNAME" \
    -e PASSWORD="$PASSWORD" \
    -e OLLAMA_URL="$OLLAMA_URL" \
    -e OLLAMA_MODEL="$OLLAMA_MODEL" \
    -e PIPER_VOICE="$PIPER_VOICE" \
    -e PIPELINE_NAME="$PIPELINE_NAME" \
    home-assistant python3 - <<'PYEOF'
import asyncio
import os
import sys
import aiohttp

BASE = 'http://localhost:8123'
WS = 'ws://localhost:8123/api/websocket'
USERNAME = os.environ['USERNAME']
PASSWORD = os.environ['PASSWORD']
OLLAMA_URL = os.environ['OLLAMA_URL']
OLLAMA_MODEL = os.environ['OLLAMA_MODEL']
PIPER_VOICE = os.environ['PIPER_VOICE']
PIPELINE_NAME = os.environ['PIPELINE_NAME']


async def get_token(session):
    response = await session.post(
        f'{BASE}/auth/login_flow',
        json={
            'client_id': f'{BASE}/',
            'handler': ['homeassistant', None],
            'redirect_uri': f'{BASE}/?auth_callback=1',
        },
    )
    flow = await response.json()
    response = await session.post(
        f'{BASE}/auth/login_flow/{flow["flow_id"]}',
        json={'username': USERNAME, 'password': PASSWORD},
    )
    result = await response.json()
    if 'result' not in result:
        raise SystemExit(f'login failed: {result}')
    response = await session.post(
        f'{BASE}/auth/token',
        data={
            'client_id': f'{BASE}/',
            'grant_type': 'authorization_code',
            'code': result['result'],
        },
    )
    body = await response.json()
    if 'access_token' not in body:
        raise SystemExit(f'token exchange failed: {body}')
    return body['access_token']


async def get_entries(session, headers, domain):
    response = await session.get(
        f'{BASE}/api/config/config_entries/entry', headers=headers
    )
    entries = await response.json()
    return [entry for entry in entries if entry.get('domain') == domain]


async def complete_flow(session, headers, handler, steps):
    response = await session.post(
        f'{BASE}/api/config/config_entries/flow',
        json={'handler': handler}, headers=headers,
    )
    flow = await response.json()
    for step_data in steps:
        if flow.get('type') == 'create_entry':
            return flow
        if flow.get('type') == 'abort':
            raise SystemExit(f'{handler} flow aborted: {flow}')
        response = await session.post(
            f'{BASE}/api/config/config_entries/flow/{flow["flow_id"]}',
            json=step_data, headers=headers,
        )
        flow = await response.json()
    if flow.get('type') != 'create_entry':
        raise SystemExit(f'{handler} flow did not complete: {flow}')
    return flow


async def setup_integration(session, headers, handler, label, match_fn, steps):
    for entry in await get_entries(session, headers, handler):
        if match_fn(entry):
            print(f'{label}: entry {entry["entry_id"]} already exists', flush=True)
            return entry['entry_id']
    flow = await complete_flow(session, headers, handler, steps)
    entry_id = flow['result']['entry_id']
    print(f'{label}: created entry {entry_id}', flush=True)
    return entry_id


async def ws_call(ws, msg_id, payload):
    payload['id'] = msg_id
    await ws.send_json(payload)
    while True:
        response = await ws.receive_json()
        if response.get('id') == msg_id:
            return response


async def main():
    timeout = aiohttp.ClientTimeout(total=120)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        token = await get_token(session)
        headers = {'Authorization': f'Bearer {token}'}

        whisper_entry = await setup_integration(
            session, headers, 'wyoming', 'wyoming-whisper',
            lambda entry: entry['data'].get('host') == 'wyoming-whisper',
            [{'host': 'wyoming-whisper', 'port': 10300}],
        )
        piper_entry = await setup_integration(
            session, headers, 'wyoming', 'wyoming-piper',
            lambda entry: entry['data'].get('host') == 'wyoming-piper',
            [{'host': 'wyoming-piper', 'port': 10200}],
        )
        ollama_entry = await setup_integration(
            session, headers, 'ollama', 'ollama',
            lambda entry: entry['data'].get('url') == OLLAMA_URL
                and entry['data'].get('model') == OLLAMA_MODEL,
            [
                {'url': OLLAMA_URL},
                {'model': OLLAMA_MODEL, 'llm_hass_api': 'assist', 'max_history': 20},
            ],
        )

        async with session.ws_connect(WS) as ws:
            await ws.receive_json()
            await ws.send_json({'type': 'auth', 'access_token': token})
            ack = await ws.receive_json()
            if ack.get('type') != 'auth_ok':
                raise SystemExit(f'ws auth failed: {ack}')

            entities = (await ws_call(ws, 1, {
                'type': 'config/entity_registry/list'
            }))['result']

            def find_entity(domain, entry_id):
                for item in entities:
                    if item.get('config_entry_id') != entry_id:
                        continue
                    if item['entity_id'].startswith(domain + '.'):
                        return item['entity_id']
                raise SystemExit(f'no {domain} entity for entry {entry_id}')

            stt_entity = find_entity('stt', whisper_entry)
            tts_entity = find_entity('tts', piper_entry)
            conversation_entity = find_entity('conversation', ollama_entry)

            pipelines_response = await ws_call(ws, 2, {
                'type': 'assist_pipeline/pipeline/list'
            })
            for existing in pipelines_response['result']['pipelines']:
                if existing['name'] == PIPELINE_NAME:
                    print(f'pipeline {existing["id"]} already exists', flush=True)
                    await ws_call(ws, 3, {
                        'type': 'assist_pipeline/pipeline/set_preferred',
                        'pipeline_id': existing['id'],
                    })
                    return

            create_response = await ws_call(ws, 4, {
                'type': 'assist_pipeline/pipeline/create',
                'name': PIPELINE_NAME,
                'language': 'en',
                'conversation_engine': conversation_entity,
                'conversation_language': 'en',
                'stt_engine': stt_entity,
                'stt_language': 'en',
                'tts_engine': tts_entity,
                'tts_language': 'en-us',
                'tts_voice': PIPER_VOICE,
                'wake_word_entity': None,
                'wake_word_id': None,
            })
            if not create_response.get('success'):
                raise SystemExit(f'pipeline create failed: {create_response}')
            pipeline_id = create_response['result']['id']
            await ws_call(ws, 5, {
                'type': 'assist_pipeline/pipeline/set_preferred',
                'pipeline_id': pipeline_id,
            })
            print(f'created pipeline {pipeline_id}', flush=True)


asyncio.run(main())
PYEOF
`

func setupVoicePipeline(ctx *pulumi.Context, homeAssistant *docker.Container, whisper *docker.Container, piper *docker.Container, secrets map[string]string, voice voiceConfig) error {
	_, err := local.NewCommand(ctx, "home-assistant-voice-pipeline", &local.CommandArgs{
		Create: pulumi.String(voicePipelineScript),
		Update: pulumi.String(voicePipelineScript),
		Environment: pulumi.StringMap{
			"USERNAME":      pulumi.String(secrets["HOME_ASSISTANT_USERNAME"]),
			"PASSWORD":      pulumi.String(secrets["HOME_ASSISTANT_PASSWORD"]),
			"OLLAMA_URL":    pulumi.String(voice.OllamaURL),
			"OLLAMA_MODEL":  pulumi.String(voice.OllamaModel),
			"PIPER_VOICE":   pulumi.String(voice.PiperVoice),
			"PIPELINE_NAME": pulumi.String(voice.PipelineName),
		},
		Triggers: pulumi.Array{
			homeAssistant.ID(),
			whisper.ID(),
			piper.ID(),
			pulumi.String(voicePipelineScript),
		},
	}, pulumi.DependsOn([]pulumi.Resource{homeAssistant, whisper, piper}),
		pulumi.AdditionalSecretOutputs([]string{"environment", "stdout", "stderr"}))
	return err
}

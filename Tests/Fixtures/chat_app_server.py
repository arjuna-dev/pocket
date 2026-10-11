#!/usr/bin/env python3
"""Offline JSON-RPC fixture, including notifications before their RPC response."""
import json
import os
import sys
import time

mode = os.path.basename(os.path.dirname(os.getcwd()))
signed_in = True

def send(message):
    payload = json.dumps(message) + '\n'
    # Exercise line buffering across partial reads.
    sys.stdout.write(payload[:7])
    sys.stdout.flush()
    time.sleep(0.002)
    sys.stdout.write(payload[7:])
    sys.stdout.flush()

for line in sys.stdin:
    request = json.loads(line)
    if 'method' not in request or 'id' not in request:
        continue
    method = request['method']
    params = request.get('params', {})
    result = {}
    if method == 'account/read':
        if mode == 'timeout':
            continue
        if mode == 'disconnect':
            sys.exit(0)
        result = {'account': {'type': 'chatgpt', 'email': 'fixture@example.com'} if signed_in else None}
    elif method == 'account/login/start':
        send({'method': 'account/login/completed', 'params': {'loginId': 'login', 'success': True}})
        result = {'loginId': 'login', 'authUrl': 'https://auth.openai.com/fixture'}
    elif method == 'model/list':
        result = {'data': [{'model': 'fixture', 'isDefault': True, 'supportedReasoningEfforts': [{'reasoningEffort': 'low'}]}]}
    elif method == 'thread/start':
        assert params['ephemeral'] and params['sandbox'] == 'read-only' and params['approvalPolicy'] == 'never'
        result = {'thread': {'id': 'thread'}}
    elif method == 'turn/start':
        assert params['outputSchema']['additionalProperties'] is False
        if mode == 'error':
            send({'id': request['id'], 'error': {'code': -1, 'message': 'Fixture failure'}})
            continue
        state = json.loads(params['input'][0]['text'].split('Workspace JSON:\n')[1].split('\n\nUser request:')[0])
        change = {'baseRevision': state['revision'], 'layout': {'columns': 4, 'rows': 3}, 'screenUpdates': [], 'message': 'Ready.'}
        value = '{invalid' if mode == 'invalid' else json.dumps(change)
        send({'method': 'item/completed', 'params': {'threadId': 'thread', 'item': {'type': 'agentMessage', 'text': value}}})
        send({'method': 'turn/completed', 'params': {'threadId': 'thread', 'turn': {'id': 'turn', 'status': 'completed', 'items': []}}})
        result = {'turn': {'id': 'turn'}}
    send({'id': request['id'], 'result': result})

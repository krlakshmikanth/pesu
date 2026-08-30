import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveDaytonaAPIKey } from './daytona-key';
import { hasValidBridgeToken, workspaceFailureMessage } from '../app/api/daytona/workspaces/route';
import { createWithTierManagedNetworkFallback, isTierManagedNetworkError } from './daytona-runtime';
import {
  buildWorkspaceFiles,
  isAllowedLocalBridgeRequest,
  runDaytonaWorkspace,
  validateWorkspaceRequest,
  type WorkspaceRuntime,
} from './daytona-workspace';

test('resolves the Daytona key from the local bearer header with an environment fallback', () => {
  const requestKey = resolveDaytonaAPIKey({
    authorizationHeader: 'Bearer request-key',
    environment: { DAYTONA_API_KEY: ' environment-key ' },
  });
  assert.equal(requestKey, 'request-key');

  const environmentKey = resolveDaytonaAPIKey({
    authorizationHeader: null,
    environment: { DAYTONA_API_KEY: ' environment-key ' },
  });
  assert.equal(environmentKey, 'environment-key');

  const unavailable = resolveDaytonaAPIKey({
    authorizationHeader: 'Basic not-supported',
    environment: {},
  });
  assert.equal(unavailable, undefined);
});

test('turns missing Secret and permission failures into actionable messages', () => {
  assert.match(
    workspaceFailureMessage('Secrets not found: openai-api-key'),
    /organisation Secret named openai-api-key/,
  );
  assert.match(workspaceFailureMessage('Access denied'), /sandbox permissions/);
  assert.match(workspaceFailureMessage('socket closed'), /could not complete/);
});

test('recognises Daytona tiers where network policy is managed by the organisation', () => {
  assert.equal(
    isTierManagedNetworkError(
      new Error('Network access is restricted and cannot be overridden at the sandbox level.'),
    ),
    true,
  );
  assert.equal(isTierManagedNetworkError(new Error('network policy unavailable')), false);
});

test('retries sandbox creation without per-sandbox network policy on managed tiers', async () => {
  const attempts: Array<Record<string, unknown>> = [];
  const sandbox = await createWithTierManagedNetworkFallback(async (options) => {
    attempts.push(options);
    if (attempts.length === 1) {
      throw new Error('Network access is restricted and cannot be overridden at the sandbox level.');
    }
    return { id: 'managed-tier' };
  }, {
    ttlMinutes: 60,
    domainAllowList: 'api.openai.com',
    secrets: { OPENAI_API_KEY: 'openai-api-key' },
  });
  assert.equal(sandbox.id, 'managed-tier');
  assert.equal(attempts.length, 2);
  assert.equal(attempts[1].domainAllowList, undefined);
  assert.deepEqual(attempts[1].secrets, { OPENAI_API_KEY: 'openai-api-key' });
});

test('requires the private per-launch token on local bridge requests', () => {
  const authorized = new Request('http://127.0.0.1:3000/api/daytona/workspaces', {
    headers: { 'X-Pesu-Bridge-Token': 'launch-token' },
  });
  assert.equal(hasValidBridgeToken(authorized, 'launch-token'), true);
  assert.equal(hasValidBridgeToken(authorized, 'different-token'), false);
  assert.equal(hasValidBridgeToken(authorized, undefined), false);
});

const validRequest = {
  meetingId: 'meeting-42',
  meetingTitle: 'Private roadmap review',
  brief: 'We agreed to prototype a small status page.',
  decisions: [{ id: 'decision-1', text: 'Build a status page', evidence: 'Keep it deliberately small.' }],
  selectedAction: 'Build a status page',
  userInstruction: 'Use a calm, accessible visual style.',
};

test('validates the explicit, bounded meeting context contract', () => {
  assert.deepEqual(validateWorkspaceRequest(validRequest), validRequest);

  assert.throws(
    () => validateWorkspaceRequest({ ...validRequest, transcript: 'private transcript' }),
    /Unexpected field: transcript/,
  );
  assert.throws(
    () => validateWorkspaceRequest({ ...validRequest, selectedAction: ' '.repeat(10), userInstruction: undefined }),
    /selectedAction or userInstruction/,
  );
  assert.throws(
    () => validateWorkspaceRequest({ ...validRequest, decisions: Array(9).fill(validRequest.decisions[0]) }),
    /at most 8 entries/,
  );
});

test('accepts a custom-instruction-only build when there are no decisions', () => {
  const input = validateWorkspaceRequest({
    meetingId: 'meeting-custom',
    meetingTitle: 'Design chat',
    brief: 'Explore a small visual prototype.',
    decisions: [],
    userInstruction: 'Build an interactive colour palette.',
  });

  assert.equal(input.selectedAction, undefined);
  assert.equal(input.userInstruction, 'Build an interactive colour palette.');
});

test('only accepts localhost bridge requests and localhost browser origins', () => {
  assert.equal(isAllowedLocalBridgeRequest(new Request('http://127.0.0.1:3000/api/daytona/workspaces')), true);
  assert.equal(
    isAllowedLocalBridgeRequest(new Request('http://localhost:3000/api/daytona/workspaces', {
      headers: { origin: 'http://localhost:3000' },
    })),
    true,
  );
  assert.equal(isAllowedLocalBridgeRequest(new Request('https://pesu.example/api/daytona/workspaces')), false);
  assert.equal(
    isAllowedLocalBridgeRequest(new Request('http://localhost:3000/api/daytona/workspaces', {
      headers: { origin: 'https://attacker.example' },
    })),
    false,
  );
});

test('builds task and context files without shell-escaping user text', () => {
  const input = validateWorkspaceRequest({
    ...validRequest,
    userInstruction: 'Include `ticks` and $(do-not-run-this).',
  });
  const files = buildWorkspaceFiles(input);

  assert.deepEqual(Object.keys(files).sort(), ['pesu-context.json', 'task.md']);
  assert.match(files['task.md'], /\$\(do-not-run-this\)/);
  assert.equal(JSON.parse(files['pesu-context.json']).selectedAction, 'Build a status page');
  assert.ok(!files['pesu-context.json'].includes('transcript'));
  assert.ok(!files['pesu-context.json'].includes('audio'));
});

test('streams genuine runtime progress and preserves a ready sandbox', async () => {
  const calls: string[] = [];
  const runtime: WorkspaceRuntime = {
    async createSandbox() {
      calls.push('create');
      return {
        id: 'sandbox-123',
        async uploadWorkspaceFiles() { calls.push('upload'); },
        async installAgent() { calls.push('install'); },
        async runAgent(onActivity) {
          calls.push('agent');
          onActivity('Created index.html', 'stdout');
        },
        async prepareForPreview() { calls.push('secure'); },
        async startPreviewServer() { calls.push('server'); },
        async getSignedPreviewUrl() {
          calls.push('preview');
          return 'https://preview.example';
        },
        async delete() { calls.push('delete'); },
      };
    },
  };

  const events: Array<{ type: string; [key: string]: unknown }> = [];
  await runDaytonaWorkspace(
    validateWorkspaceRequest(validRequest),
    runtime,
    (event) => events.push(event),
  );

  assert.deepEqual(calls, ['create', 'upload', 'install', 'agent', 'secure', 'server', 'preview']);
  assert.equal(events.at(-1)?.type, 'ready');
  assert.equal(events.at(-1)?.previewUrl, 'https://preview.example');
  assert.equal(events.at(-1)?.sandboxId, 'sandbox-123');
  assert.ok(events.some((event) => event.type === 'activity' && event.message === 'Created index.html'));
});

test('deletes a partially-created sandbox when execution fails', async () => {
  let deleted = false;
  const runtime: WorkspaceRuntime = {
    async createSandbox() {
      return {
        id: 'sandbox-failed',
        async uploadWorkspaceFiles() {},
        async installAgent() { throw new Error('npm unavailable'); },
        async runAgent() {},
        async prepareForPreview() {},
        async startPreviewServer() {},
        async getSignedPreviewUrl() { return 'unused'; },
        async delete() { deleted = true; },
      };
    },
  };
  const statuses: string[] = [];

  await assert.rejects(
    runDaytonaWorkspace(
      validateWorkspaceRequest(validRequest),
      runtime,
      (event) => statuses.push(event.type),
    ),
    /npm unavailable/,
  );

  assert.equal(deleted, true);
  assert.deepEqual(statuses, ['preparing', 'creating_sandbox', 'installing_agent']);
});

test('fails closed before preview when secrets or outbound network cannot be removed', async () => {
  let previewStarted = false;
  let deleted = false;
  const runtime: WorkspaceRuntime = {
    async createSandbox() {
      return {
        id: 'sandbox-unsecured',
        async uploadWorkspaceFiles() {},
        async installAgent() {},
        async runAgent() {},
        async prepareForPreview() { throw new Error('network policy unavailable'); },
        async startPreviewServer() { previewStarted = true; },
        async getSignedPreviewUrl() { return 'unused'; },
        async delete() { deleted = true; },
      };
    },
  };

  await assert.rejects(
    runDaytonaWorkspace(validateWorkspaceRequest(validRequest), runtime, () => undefined),
    /network policy unavailable/,
  );
  assert.equal(previewStarted, false);
  assert.equal(deleted, true);
});

test('deletes the sandbox and stops the pipeline after client cancellation', async () => {
  const abortController = new AbortController();
  let secured = false;
  let previewStarted = false;
  let deleted = false;
  const runtime: WorkspaceRuntime = {
    async createSandbox() {
      return {
        id: 'sandbox-cancelled',
        async uploadWorkspaceFiles() {},
        async installAgent() {},
        async runAgent() { abortController.abort(); },
        async prepareForPreview() { secured = true; },
        async startPreviewServer() { previewStarted = true; },
        async getSignedPreviewUrl() { return 'unused'; },
        async delete() { deleted = true; },
      };
    },
  };

  await assert.rejects(
    runDaytonaWorkspace(
      validateWorkspaceRequest(validRequest),
      runtime,
      () => undefined,
      abortController.signal,
    ),
    /cancelled/,
  );
  assert.equal(secured, false);
  assert.equal(previewStarted, false);
  assert.equal(deleted, true);
});

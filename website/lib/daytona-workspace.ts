const REQUEST_FIELDS = new Set([
  'meetingId',
  'meetingTitle',
  'brief',
  'decisions',
  'selectedAction',
  'userInstruction',
]);

const DECISION_FIELDS = new Set(['id', 'text', 'evidence']);

export type WorkspaceDecision = {
  id: string;
  text: string;
  evidence?: string;
};

export type WorkspaceRequest = {
  meetingId: string;
  meetingTitle: string;
  brief: string;
  decisions: WorkspaceDecision[];
  selectedAction?: string;
  userInstruction?: string;
};

export type WorkspaceEvent = {
  type:
    | 'preparing'
    | 'creating_sandbox'
    | 'installing_agent'
    | 'running_agent'
    | 'activity'
    | 'starting_preview'
    | 'creating_preview'
    | 'ready'
    | 'failed';
  message: string;
  stream?: 'stdout' | 'stderr';
  sandboxId?: string;
  previewUrl?: string;
  artifactHtml?: string;
};

export interface WorkspaceSandbox {
  id: string;
  uploadWorkspaceFiles(files: Record<string, string>): Promise<void>;
  installAgent(): Promise<void>;
  runAgent(
    onActivity: (message: string, stream: 'stdout' | 'stderr') => void,
    signal?: AbortSignal,
  ): Promise<void>;
  getArtifactHTML(): Promise<string>;
  prepareForPreview(): Promise<void>;
  startPreviewServer(): Promise<void>;
  getSignedPreviewUrl(): Promise<string>;
  delete(): Promise<void>;
}

export interface WorkspaceRuntime {
  createSandbox(): Promise<WorkspaceSandbox>;
}

function record(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new WorkspaceValidationError(`${label} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function boundedString(
  value: unknown,
  field: string,
  maxLength: number,
  options: { optional?: boolean } = {},
): string | undefined {
  if (value === undefined && options.optional) return undefined;
  if (typeof value !== 'string') {
    throw new WorkspaceValidationError(`${field} must be a string.`);
  }
  const result = value.trim();
  if (!result && options.optional) return undefined;
  if (!result || result.length > maxLength) {
    throw new WorkspaceValidationError(`${field} must contain 1-${maxLength} characters.`);
  }
  return result;
}

function rejectUnexpectedFields(value: Record<string, unknown>, allowed: Set<string>) {
  const unexpected = Object.keys(value).find((field) => !allowed.has(field));
  if (unexpected) throw new WorkspaceValidationError(`Unexpected field: ${unexpected}.`);
}

export class WorkspaceValidationError extends Error {}
export class WorkspaceCancelledError extends Error {}

function isLoopbackHostname(hostname: string): boolean {
  const normalized = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  return normalized === 'localhost' || normalized === '127.0.0.1' || normalized === '::1';
}

export function isAllowedLocalBridgeRequest(request: Request): boolean {
  let requestHostname: string;
  try {
    requestHostname = new URL(request.url).hostname;
  } catch {
    return false;
  }
  if (!isLoopbackHostname(requestHostname)) return false;

  const forwardedHost = request.headers.get('x-forwarded-host');
  if (forwardedHost) {
    try {
      if (!isLoopbackHostname(new URL(`http://${forwardedHost}`).hostname)) return false;
    } catch {
      return false;
    }
  }

  const origin = request.headers.get('origin');
  if (origin) {
    try {
      if (!isLoopbackHostname(new URL(origin).hostname)) return false;
    } catch {
      return false;
    }
  }
  return true;
}

export function validateWorkspaceRequest(value: unknown): WorkspaceRequest {
  const input = record(value, 'Request');
  rejectUnexpectedFields(input, REQUEST_FIELDS);

  if (!Array.isArray(input.decisions) || input.decisions.length > 8) {
    throw new WorkspaceValidationError('decisions must be an array with at most 8 entries.');
  }

  const decisions = input.decisions.map((value, index) => {
    const decision = record(value, `decisions[${index}]`);
    rejectUnexpectedFields(decision, DECISION_FIELDS);
    const evidence = boundedString(decision.evidence, `decisions[${index}].evidence`, 500, {
      optional: true,
    });
    return {
      id: boundedString(decision.id, `decisions[${index}].id`, 40) as string,
      text: boundedString(decision.text, `decisions[${index}].text`, 500) as string,
      ...(evidence ? { evidence } : {}),
    };
  });

  const userInstruction = boundedString(input.userInstruction, 'userInstruction', 2_000, {
    optional: true,
  });
  const selectedAction = boundedString(input.selectedAction, 'selectedAction', 1_000, {
    optional: true,
  });
  if (!selectedAction && !userInstruction) {
    throw new WorkspaceValidationError('selectedAction or userInstruction is required.');
  }

  return {
    meetingId: boundedString(input.meetingId, 'meetingId', 200) as string,
    meetingTitle: boundedString(input.meetingTitle, 'meetingTitle', 200) as string,
    brief: boundedString(input.brief, 'brief', 2_000) as string,
    decisions,
    ...(selectedAction ? { selectedAction } : {}),
    ...(userInstruction ? { userInstruction } : {}),
  };
}

export function buildWorkspaceFiles(input: WorkspaceRequest): Record<string, string> {
  const task = [
    '# Build request from Pēsu',
    '',
    'Build a small, polished, working web prototype from the explicitly shared meeting context.',
    '',
    input.selectedAction ? `Selected action: ${input.selectedAction}` : undefined,
    input.userInstruction ? `Additional instruction: ${input.userInstruction}` : undefined,
    '',
    'Read `/home/daytona/pesu-context.json` for the rest of the approved context.',
    'Create a dependency-free static site in `/home/daytona/workspace`.',
    'The result must include `/home/daytona/workspace/index.html` and work from a plain static HTTP server.',
    'Do not start a server. Do not request credentials. Do not include private meeting context verbatim unless it is necessary for the prototype.',
  ]
    .filter((line): line is string => line !== undefined)
    .join('\n');

  return {
    'task.md': `${task}\n`,
    'pesu-context.json': `${JSON.stringify(input, null, 2)}\n`,
  };
}

export async function runDaytonaWorkspace(
  input: WorkspaceRequest,
  runtime: WorkspaceRuntime,
  emit: (event: WorkspaceEvent) => void,
  signal?: AbortSignal,
): Promise<void> {
  let sandbox: WorkspaceSandbox | undefined;
  const requireActive = () => {
    if (signal?.aborted) throw new WorkspaceCancelledError('Workspace build was cancelled.');
  };

  try {
    requireActive();
    emit({ type: 'preparing', message: 'Preparing the approved meeting context…' });
    emit({ type: 'creating_sandbox', message: 'Creating an isolated Daytona sandbox…' });
    sandbox = await runtime.createSandbox();
    requireActive();

    await sandbox.uploadWorkspaceFiles(buildWorkspaceFiles(input));
    requireActive();

    emit({ type: 'installing_agent', message: 'Preparing the Codex coding agent…' });
    await sandbox.installAgent();
    requireActive();

    emit({ type: 'running_agent', message: 'Codex is building the prototype…' });
    await sandbox.runAgent((message, stream) => {
      const safeMessage = sanitizeActivity(message);
      if (safeMessage) emit({ type: 'activity', message: safeMessage, stream });
    }, signal);
    requireActive();

    const artifactHtml = await sandbox.getArtifactHTML();
    requireActive();

    await sandbox.prepareForPreview();
    requireActive();
    emit({ type: 'starting_preview', message: 'Starting the generated app…' });
    await sandbox.startPreviewServer();
    requireActive();

    emit({ type: 'creating_preview', message: 'Creating a private preview link…' });
    const previewUrl = await sandbox.getSignedPreviewUrl();
    requireActive();

    emit({
      type: 'ready',
      message: 'Your prototype is ready.',
      sandboxId: sandbox.id,
      previewUrl,
      artifactHtml,
    });
  } catch (error) {
    if (sandbox) {
      let cleanupSucceeded = false;
      for (let attempt = 0; attempt < 2 && !cleanupSucceeded; attempt += 1) {
        try {
          await sandbox.delete();
          cleanupSucceeded = true;
        } catch {
          // Retry once, then fail closed with a fixed message that cannot contain credentials.
        }
      }
      if (!cleanupSucceeded) {
        throw new AggregateError(
          [error],
          'Daytona workspace failed and sandbox cleanup could not be confirmed.',
        );
      }
    }
    throw error;
  }
}

export function sanitizeActivity(value: string): string {
  return value
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .trim()
    .slice(0, 1_200);
}

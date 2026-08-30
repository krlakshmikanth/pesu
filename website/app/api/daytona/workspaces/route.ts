import { createDaytonaRuntime } from '@/lib/daytona-runtime';
import { resolveDaytonaAPIKey } from '@/lib/daytona-key';
import {
  isAllowedLocalBridgeRequest,
  runDaytonaWorkspace,
  validateWorkspaceRequest,
  WorkspaceCancelledError,
  WorkspaceValidationError,
  type WorkspaceEvent,
} from '@/lib/daytona-workspace';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 900;

const MAX_REQUEST_BYTES = 50_000;
const encoder = new TextEncoder();

export async function GET(request: Request) {
  if (!isAllowedLocalBridgeRequest(request)) {
    return jsonError('This bridge only accepts requests from this Mac.', 403);
  }
  if (!hasValidBridgeToken(request)) {
    return jsonError('This local bridge request is not authorized.', 401);
  }
  return Response.json({ service: 'pesu-daytona-bridge', status: 'ready' }, {
    headers: { 'Cache-Control': 'no-store' },
  });
}

function jsonError(message: string, status: number) {
  return Response.json({ error: message }, { status });
}

export async function POST(request: Request) {
  if (!isAllowedLocalBridgeRequest(request)) {
    return jsonError('This bridge only accepts requests from this Mac.', 403);
  }
  if (!hasValidBridgeToken(request)) {
    return jsonError('This local bridge request is not authorized.', 401);
  }

  if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    return jsonError('This bridge only accepts JSON requests.', 415);
  }

  const contentLength = Number(request.headers.get('content-length') || '0');
  if (contentLength > MAX_REQUEST_BYTES) {
    return jsonError('The shared meeting context is too large.', 413);
  }

  let input;
  try {
    const rawBody = await request.text();
    if (Buffer.byteLength(rawBody, 'utf8') > MAX_REQUEST_BYTES) {
      return jsonError('The shared meeting context is too large.', 413);
    }
    input = validateWorkspaceRequest(JSON.parse(rawBody));
  } catch (error) {
    const message = error instanceof WorkspaceValidationError
      ? error.message
      : 'The shared meeting context is invalid.';
    return jsonError(message, 400);
  }

  const daytonaApiKey = resolveDaytonaAPIKey({
    authorizationHeader: request.headers.get('authorization'),
  });
  if (!daytonaApiKey) {
    return jsonError('Add your Daytona API key in Pēsu Settings and try again.', 503);
  }

  const runtime = createDaytonaRuntime({
    apiKey: daytonaApiKey,
    openAISecretName: process.env.DAYTONA_OPENAI_SECRET_NAME,
  });
  let cancelled = false;
  const abortController = new AbortController();
  const abort = () => {
    cancelled = true;
    abortController.abort();
  };
  request.signal.addEventListener('abort', abort, { once: true });
  if (request.signal.aborted) abort();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const emit = (event: WorkspaceEvent) => {
        if (cancelled) return;
        try {
          controller.enqueue(encoder.encode(`${JSON.stringify(event)}\n`));
        } catch {
          abort();
        }
      };

      void runDaytonaWorkspace(input, runtime, emit, abortController.signal)
        .catch((error) => {
          if (error instanceof WorkspaceCancelledError) return;
          const detail = error instanceof Error ? error.message : 'Unknown Daytona error';
          console.error(
            'Daytona workspace build failed:',
            detail.replaceAll(daytonaApiKey, '[redacted]').slice(0, 500),
          );
          emit({
            type: 'failed',
            message: workspaceFailureMessage(detail),
          });
        })
        .finally(() => {
          request.signal.removeEventListener('abort', abort);
          if (!cancelled) controller.close();
        });
    },
    cancel() {
      abort();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      'Content-Type': 'application/x-ndjson; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

export function hasValidBridgeToken(
  request: Request,
  expected: string | undefined = process.env.PESU_BRIDGE_TOKEN,
): boolean {
  if (!expected) return false;
  return request.headers.get('x-pesu-bridge-token') === expected;
}

export function workspaceFailureMessage(detail: string): string {
  if (/secrets? not found:\s*openai-api-key/i.test(detail)) {
    return 'Daytona needs an organisation Secret named openai-api-key, restricted to api.openai.com.';
  }
  if (/access denied|unauthori[sz]ed|forbidden/i.test(detail)) {
    return 'The saved Daytona key cannot create this workspace. Check its sandbox permissions and organisation.';
  }
  return 'Daytona could not complete the build. Check the bridge configuration and try again.';
}

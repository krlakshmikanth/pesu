import { createDaytonaRuntime } from '@/lib/daytona-runtime';
import { resolveDaytonaAPIKey } from '@/lib/daytona-key';
import {
  AIProviderConfigurationError,
  resolveAIProviderConfig,
  type AIProviderRuntimeConfig,
} from '@/lib/daytona-ai-provider';
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
  let aiProvider: AIProviderRuntimeConfig;
  try {
    aiProvider = resolveAIProviderConfig({
      provider: request.headers.get('x-pesu-ai-provider'),
      authorization: request.headers.get('x-pesu-ai-authorization'),
      azureEndpoint: request.headers.get('x-pesu-azure-endpoint'),
      azureDeployment: request.headers.get('x-pesu-azure-deployment'),
    });
  } catch (error) {
    const message = error instanceof AIProviderConfigurationError
      ? error.message
      : 'The selected AI provider settings are invalid.';
    return jsonError(message, 503);
  }

  const runtime = createDaytonaRuntime({
    apiKey: daytonaApiKey,
    aiProvider,
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
            detail
              .replaceAll(daytonaApiKey, '[redacted]')
              .replaceAll(aiProvider.apiKey, '[redacted]')
              .slice(0, 500),
          );
          emit({
            type: 'failed',
            message: workspaceFailureMessage(detail, aiProvider.kind),
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

export function workspaceFailureMessage(
  detail: string,
  provider: 'openai' | 'azure-openai' = 'openai',
): string {
  const providerName = provider === 'azure-openai' ? 'Azure OpenAI' : 'OpenAI';
  if (detail.includes('PESU_AI_API_KEY_REJECTED')) {
    return `${providerName} rejected the saved API key. Update it in Pēsu Settings and try again.`;
  }
  if (detail.includes('PESU_AI_USAGE_LIMIT')) {
    return `${providerName} could not run this build because of a rate, capacity, usage, or billing limit. Wait briefly, then try again.`;
  }
  if (detail.includes('PESU_AZURE_DEPLOYMENT_INVALID')) {
    return 'Azure OpenAI could not find or use that deployment. Check the endpoint, deployment name, and Responses API support.';
  }
  if (detail.includes('PESU_AZURE_ACCESS_DENIED')) {
    return 'Azure OpenAI denied access. Check the API key, resource firewall or private-network policy, and deployment permissions.';
  }
  if (detail.includes('PESU_AZURE_REQUEST_REJECTED')) {
    return 'Azure OpenAI rejected the generation request. Check that the selected deployment supports the Responses API.';
  }
  if (detail.includes('PESU_AI_NETWORK_UNAVAILABLE')) {
    return `${providerName} could not be reached from the Daytona sandbox. Check the Daytona network policy and Azure resource firewall, then try again.`;
  }
  if (/access denied|unauthori[sz]ed|forbidden/i.test(detail)) {
    return 'The saved Daytona key cannot create this workspace. Check its sandbox permissions and organisation.';
  }
  return 'Daytona could not complete the build. Check the bridge configuration and try again.';
}

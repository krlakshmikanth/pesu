export type AIProviderRuntimeConfig = {
  kind: 'openai' | 'azure-openai';
  apiKey: string;
  responseUrl: string;
  model: string;
  allowedHost: string;
};

export class AIProviderConfigurationError extends Error {}

type ProviderHeaders = {
  provider: string | null;
  authorization: string | null;
  azureEndpoint: string | null;
  azureDeployment: string | null;
};

function bearerToken(header: string | null): string | undefined {
  const match = header && /^Bearer ([^\s]{1,4096})$/i.exec(header.trim());
  return match?.[1];
}

function azureConfiguration(endpointValue: string | null, deploymentValue: string | null) {
  if (!endpointValue || Buffer.byteLength(endpointValue, 'utf8') > 512) {
    throw new AIProviderConfigurationError('Add a valid Azure OpenAI endpoint in Pēsu Settings.');
  }
  let endpoint: URL;
  try {
    endpoint = new URL(endpointValue || '');
  } catch {
    throw new AIProviderConfigurationError('Add a valid Azure OpenAI endpoint in Pēsu Settings.');
  }
  const hostname = endpoint.hostname.toLowerCase();
  if (
    endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.port ||
    endpoint.search || endpoint.hash || !hostname.endsWith('.openai.azure.com') ||
    hostname === 'openai.azure.com' ||
    !['/', '/openai/v1', '/openai/v1/'].includes(endpoint.pathname)
  ) {
    throw new AIProviderConfigurationError('Add a valid HTTPS *.openai.azure.com endpoint in Pēsu Settings.');
  }
  const deployment = deploymentValue?.trim() || '';
  if (!/^[A-Za-z0-9._-]{1,128}$/.test(deployment)) {
    throw new AIProviderConfigurationError('Add a valid Azure OpenAI deployment name in Pēsu Settings.');
  }
  return {
    responseUrl: `https://${hostname}/openai/v1/responses`,
    deployment,
    hostname,
  };
}

export function resolveAIProviderConfig(headers: ProviderHeaders): AIProviderRuntimeConfig {
  const apiKey = bearerToken(headers.authorization);
  if (!apiKey) {
    throw new AIProviderConfigurationError('Add the selected AI provider API key in Pēsu Settings.');
  }
  if (headers.provider === 'openai') {
    return {
      kind: 'openai',
      apiKey,
      responseUrl: 'https://api.openai.com/v1/responses',
      model: 'gpt-5.1-codex-mini',
      allowedHost: 'api.openai.com',
    };
  }
  if (headers.provider === 'azure-openai') {
    const azure = azureConfiguration(headers.azureEndpoint, headers.azureDeployment);
    return {
      kind: 'azure-openai',
      apiKey,
      responseUrl: azure.responseUrl,
      model: azure.deployment,
      allowedHost: azure.hostname,
    };
  }
  throw new AIProviderConfigurationError('Choose OpenAI or Azure OpenAI in Pēsu Settings.');
}

export function publicProviderConfiguration(config: AIProviderRuntimeConfig) {
  return {
    kind: config.kind,
    responseUrl: config.responseUrl,
    model: config.model,
  };
}

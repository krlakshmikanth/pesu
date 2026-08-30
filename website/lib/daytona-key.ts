type ResolveOptions = {
  environment?: Record<string, string | undefined>;
  authorizationHeader?: string | null;
};

function bearerToken(header: string | null | undefined): string | undefined {
  if (!header) return undefined;
  const match = /^Bearer ([^\s]{1,4096})$/i.exec(header.trim());
  return match?.[1];
}

export function resolveOpenAIAPIKey(
  authorizationHeader: string | null | undefined,
): string | undefined {
  return bearerToken(authorizationHeader);
}

export function resolveDaytonaAPIKey(
  options: ResolveOptions = {},
): string | undefined {
  const requestKey = bearerToken(options.authorizationHeader);
  if (requestKey) return requestKey;

  const environment = options.environment ?? process.env;
  const environmentKey = environment.DAYTONA_API_KEY?.trim();
  if (environmentKey) return environmentKey;
  return undefined;
}

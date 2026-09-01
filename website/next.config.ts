import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: 'standalone',
  serverExternalPackages: ['@daytona/sdk'],
  turbopack: {
    root: __dirname,
  },
};

export default nextConfig;

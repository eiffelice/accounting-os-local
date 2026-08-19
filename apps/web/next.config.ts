import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  transpilePackages: ['@accounting-os/db'],
};

export default nextConfig;

import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  transpilePackages: ['@accounting-os/db'],
  async headers() {
    return [
      {
        source: '/bank-logos/:path*',
        headers: [
          { key: 'Content-Security-Policy', value: "default-src 'none'; style-src 'unsafe-inline'; sandbox" },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Cache-Control', value: 'public, max-age=31536000, immutable' },
        ],
      },
    ];
  },
};

export default nextConfig;

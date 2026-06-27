/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  // The live-room SSE runner keeps per-process in-memory room state.
  // Keep a single worker so demo state stays consistent across requests.
  experimental: {
    // nothing required for the demo; placeholder for future tuning
  },
};

export default nextConfig;

export function assertSameOrigin(request: Request) {
  const origin = request.headers.get('origin');
  const fetchSite = request.headers.get('sec-fetch-site');
  const configuredOrigin = process.env.APP_BASE_URL
    ? new URL(process.env.APP_BASE_URL).origin
    : new URL(request.url).origin;
  if (!origin) {
    if (fetchSite !== 'same-origin') throw new Error('CSRF_ORIGIN_REQUIRED');
    return;
  }
  if (new URL(origin).origin !== configuredOrigin) {
    throw new Error('CSRF_ORIGIN_MISMATCH');
  }
}

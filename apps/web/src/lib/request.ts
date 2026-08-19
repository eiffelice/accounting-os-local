export function assertSameOrigin(request: Request) {
  const origin = request.headers.get('origin');
  const host = request.headers.get('host');
  if (!origin || !host) return;
  const parsed = new URL(origin);
  if (parsed.host !== host) {
    throw new Error('CSRF_ORIGIN_MISMATCH');
  }
}

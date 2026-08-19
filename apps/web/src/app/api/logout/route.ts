import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { revokeSession } from '@accounting-os/db';
import { SESSION_COOKIE } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  assertSameOrigin(request);
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (token) await revokeSession(token);
  const response = NextResponse.redirect(new URL('/login', request.url), 303);
  response.cookies.delete(SESSION_COOKIE);
  return response;
}

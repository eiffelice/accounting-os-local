import { NextResponse } from 'next/server';
import {
  createSession,
  getUserForLogin,
  recordLoginFailure,
  recordLoginSuccess,
  verifyPassword,
} from '@accounting-os/db';
import { assertSameOrigin } from '@/lib/request';
import { SESSION_COOKIE } from '@/lib/auth';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const form = await request.formData();
    const email = String(form.get('email') ?? '').trim();
    const password = String(form.get('password') ?? '');

    const user = await getUserForLogin(email);
    if (!user || user.is_locked || !verifyPassword(password, user.password_hash)) {
      if (email && !user?.is_locked) await recordLoginFailure(email);
      return NextResponse.redirect(new URL('/login?error=1', request.url), 303);
    }

    await recordLoginSuccess(user.id);
    const ttlHours = Math.max(1, Math.min(72, Number(process.env.SESSION_TTL_HOURS ?? 12)));
    const session = await createSession(user.id, ttlHours);

    const destination = user.must_change_password ? '/profile?mustChange=1' : '/';
    const response = NextResponse.redirect(new URL(destination, request.url), 303);
    response.cookies.set(SESSION_COOKIE, session.token, {
      httpOnly: true,
      sameSite: 'strict',
      secure: new URL(request.url).protocol === 'https:' || process.env.NODE_ENV === 'production',
      path: '/',
      expires: new Date(session.expiresAt),
    });
    return response;
  } catch {
    return NextResponse.redirect(new URL('/login?error=1', request.url), 303);
  }
}

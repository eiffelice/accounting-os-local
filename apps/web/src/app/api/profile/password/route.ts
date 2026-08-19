import { NextResponse } from 'next/server';
import { changePassword } from '@accounting-os/db';
import { currentUser, SESSION_COOKIE } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const next = String(form.get('newPassword') ?? '');
    const confirm = String(form.get('confirmPassword') ?? '');
    if (next !== confirm) throw new Error('new password confirmation does not match');
    await changePassword(user.id, String(form.get('currentPassword') ?? ''), next);
    const response = NextResponse.redirect(new URL('/login?passwordChanged=1', request.url), 303);
    response.cookies.delete(SESSION_COOKIE);
    return response;
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/profile?error=${msg}`, request.url), 303);
  }
}

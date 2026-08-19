import { NextResponse } from 'next/server';
import { createEmployeeMembership } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await createEmployeeMembership(user.id, companyId, {
      displayName: String(form.get('displayName') ?? ''),
      email: String(form.get('email') ?? ''),
      temporaryPassword: String(form.get('temporaryPassword') ?? ''),
      role: String(form.get('role')) as 'CFO'|'ACCOUNTING_MANAGER'|'ACCOUNTANT'|'STAFF'|'AUDITOR',
    });
    return NextResponse.redirect(new URL(`/access?company=${companyId}&ok=1`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/access?error=${msg}`, request.url), 303);
  }
}

import { NextResponse } from 'next/server';
import { updateMembership } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    const limitText = String(form.get('approvalLimit') ?? '').trim();
    await updateMembership(user.id, companyId, String(form.get('userId')), {
      role: String(form.get('role')),
      canRead: form.get('canRead') === 'on',
      canCreateDraft: form.get('canCreateDraft') === 'on',
      canApprove: form.get('canApprove') === 'on',
      canPost: form.get('canPost') === 'on',
      approvalLimit: limitText ? Number(limitText) : null,
    });
    return NextResponse.redirect(new URL(`/access?company=${companyId}&ok=1`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,120) : 'unknown');
    return NextResponse.redirect(new URL(`/access?error=${msg}`, request.url), 303);
  }
}

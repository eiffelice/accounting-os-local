import { NextResponse } from 'next/server';
import { approveRequest } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await approveRequest(user.id, String(form.get('requestId')), String(form.get('reason') ?? ''));
    return NextResponse.redirect(new URL(`/approvals?company=${companyId}&ok=${encodeURIComponent('อนุมัติแล้ว')}`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,120) : 'unknown');
    return NextResponse.redirect(new URL(`/approvals?error=${msg}`, request.url), 303);
  }
}

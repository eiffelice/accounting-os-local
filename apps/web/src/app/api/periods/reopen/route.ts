import { NextResponse } from 'next/server';
import { reopenFiscalPeriod } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await reopenFiscalPeriod(user.id, companyId, String(form.get('periodId')), String(form.get('reason') ?? ''));
    return NextResponse.redirect(new URL(`/periods?company=${companyId}&ok=${encodeURIComponent('เปิดงวดแล้ว')}`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/periods?error=${msg}`, request.url), 303);
  }
}

import { NextResponse } from 'next/server';
import { createFinancialAccount } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await createFinancialAccount(user.id, companyId, {
      kind: String(form.get('kind')) as 'BANK'|'CASH'|'E_WALLET'|'CREDIT_CARD',
      name: String(form.get('name') ?? ''),
      institution: String(form.get('institution') ?? ''),
      maskedNumber: String(form.get('maskedNumber') ?? ''),
      currency: 'THB',
    });
    return NextResponse.redirect(new URL(`/companies?company=${companyId}&ok=${encodeURIComponent('เพิ่มบัญชีแล้ว')}`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/companies?error=${msg}`, request.url), 303);
  }
}

import { NextResponse } from 'next/server';
import { createIncomeDraft } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';
import { randomUUID } from 'node:crypto';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await createIncomeDraft({
      actorId: user.id,
      companyId,
      financialAccountId: String(form.get('financialAccountId')),
      revenueAccountCode: String(form.get('accountCode')),
      amount: Number(form.get('amount')),
      txnDate: String(form.get('txnDate')),
      description: String(form.get('description')),
      idempotencyKey: `human:${user.id}:${randomUUID()}`,
      sourceType: 'HUMAN_UI_DRAFT',
    });
    return NextResponse.redirect(new URL(`/transactions?company=${companyId}&ok=1`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,120) : 'unknown');
    return NextResponse.redirect(new URL(`/transactions?error=${msg}`, request.url), 303);
  }
}

import { NextResponse } from 'next/server';
import { createContact } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    await createContact(user.id, companyId, {
      contactType: String(form.get('contactType')) as 'CUSTOMER'|'VENDOR'|'BOTH',
      displayName: String(form.get('displayName')).trim(),
      legalName: String(form.get('legalName') ?? '').trim(),
      taxId: String(form.get('taxId') ?? '').trim(),
      email: String(form.get('email') ?? '').trim(),
      phone: String(form.get('phone') ?? '').trim(),
    });
    return NextResponse.redirect(new URL(`/contacts?company=${companyId}&ok=1`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,120) : 'unknown');
    return NextResponse.redirect(new URL(`/contacts?error=${msg}`, request.url), 303);
  }
}

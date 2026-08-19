import { NextResponse } from 'next/server';
import { createCompany } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const company = await createCompany(user.id, {
      code: String(form.get('code') ?? ''),
      displayName: String(form.get('displayName') ?? ''),
      legalName: String(form.get('legalName') ?? ''),
      taxId: String(form.get('taxId') ?? ''),
    });
    return NextResponse.redirect(new URL(`/companies?company=${company.id}&ok=${encodeURIComponent('สร้างบริษัทแล้ว')}`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/companies?error=${msg}`, request.url), 303);
  }
}

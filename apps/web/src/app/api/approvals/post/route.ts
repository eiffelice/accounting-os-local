import { NextResponse } from 'next/server';
import { postApprovedJournal } from '@accounting-os/db';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);
    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    const entryNo = await postApprovedJournal(user.id, String(form.get('entryId')));
    return NextResponse.redirect(new URL(`/approvals?company=${companyId}&ok=${encodeURIComponent(`Posted ${entryNo}`)}`, request.url), 303);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,120) : 'unknown');
    return NextResponse.redirect(new URL(`/approvals?error=${msg}`, request.url), 303);
  }
}

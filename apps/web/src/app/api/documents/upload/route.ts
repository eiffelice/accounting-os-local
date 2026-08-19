import { NextResponse } from 'next/server';
import { currentUser } from '@/lib/auth';
import { assertSameOrigin } from '@/lib/request';
import { assertCompanyAccess, insertLocalDocument } from '@accounting-os/db';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

const ALLOWED = new Map([
  ['application/pdf', '.pdf'],
  ['image/jpeg', '.jpg'],
  ['image/png', '.png'],
]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(request: Request) {
  let target: string | null = null;
  try {
    assertSameOrigin(request);
    const user = await currentUser();
    if (!user) return NextResponse.redirect(new URL('/login', request.url), 303);

    const form = await request.formData();
    const companyId = String(form.get('companyId'));
    if (!UUID_RE.test(companyId)) throw new Error('invalid company id');
    await assertCompanyAccess(user.id, companyId, 'create_draft');

    const file = form.get('file');
    if (!(file instanceof File)) throw new Error('file is required');
    if (!ALLOWED.has(file.type)) throw new Error('unsupported file type');
    if (file.size <= 0 || file.size > 10 * 1024 * 1024) throw new Error('file must be 1 byte to 10 MB');

    const bytes = Buffer.from(await file.arrayBuffer());
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const storedName = `${randomUUID()}${ALLOWED.get(file.type)}`;
    const base = path.resolve(process.env.LOCAL_DOCUMENTS_DIR ?? './data/documents');
    const companyDir = path.resolve(base, companyId);
    if (!companyDir.startsWith(base + path.sep)) throw new Error('invalid document path');

    await mkdir(companyDir, { recursive: true });
    target = path.join(companyDir, storedName);
    await writeFile(target, bytes, { flag: 'wx' });

    await insertLocalDocument(user.id, companyId, {
      originalName: path.basename(file.name).slice(0, 240),
      storedName,
      mimeType: file.type,
      sizeBytes: file.size,
      sha256,
      relativePath: path.join(companyId, storedName),
    });

    return NextResponse.redirect(new URL(`/documents?company=${companyId}&ok=1`, request.url), 303);
  } catch (e) {
    if (target) {
      try { await unlink(target); } catch {}
    }
    const msg = encodeURIComponent(e instanceof Error ? e.message.slice(0,160) : 'unknown');
    return NextResponse.redirect(new URL(`/documents?error=${msg}`, request.url), 303);
  }
}

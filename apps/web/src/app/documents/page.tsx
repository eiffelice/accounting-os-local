import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { listCompaniesForUser, listLocalDocuments } from '@accounting-os/db';

const size = (n: number) => n < 1024*1024 ? `${(n/1024).toFixed(1)} KB` : `${(n/1024/1024).toFixed(1)} MB`;

export default async function DocumentsPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const docs = await listLocalDocuments(selected.id);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead"><div><p className="eyebrow">LOCAL DOCUMENT STORE</p><h1>เอกสาร</h1><p className="muted">ไฟล์อยู่ใน ./data/documents ไม่ถูกส่ง Cloud</p></div></div>
      {params.ok ? <div className="successBox">อัปโหลดไฟล์ Local แล้ว</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}
      <section className="grid">
        <article className="panel">
          <h3>อัปโหลด</h3>
          <form className="formStack" action="/api/documents/upload" method="post" encType="multipart/form-data">
            <input type="hidden" name="companyId" value={selected.id} />
            <label>PDF / JPG / PNG
              <input type="file" name="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" required />
            </label>
            <button className="primaryBtn" type="submit">เก็บในเครื่อง</button>
          </form>
          <p className="muted">จำกัด 10 MB/ไฟล์ • เก็บ SHA-256 เพื่อ chain of custody เบื้องต้น</p>
        </article>
        <article className="panel">
          <h3>ไฟล์ล่าสุด ({docs.length})</h3>
          <div className="accountList">
            {docs.map((d: any) => <div className="accountRow" key={d.id}><div className="accountIcon">📄</div><div className="grow"><b>{d.original_name}</b><span>{d.mime_type} · {size(Number(d.size_bytes))}</span></div><div className="right"><span>{d.uploaded_by_name}</span><span>{String(d.sha256).slice(0,12)}…</span></div></div>)}
          </div>
        </article>
      </section>
    </AppShell>
  );
}

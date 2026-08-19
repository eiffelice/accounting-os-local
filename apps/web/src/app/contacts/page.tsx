import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { listCompaniesForUser, listContacts } from '@accounting-os/db';

export default async function ContactsPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;
  const contacts = await listContacts(selected.id);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead"><div><p className="eyebrow">MASTER DATA</p><h1>ลูกค้า / คู่ค้า</h1></div></div>
      {params.ok ? <div className="successBox">เพิ่มข้อมูลแล้ว</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}
      <section className="grid">
        <article className="panel">
          <h3>เพิ่ม Contact</h3>
          <form className="formStack" action="/api/contacts" method="post">
            <input type="hidden" name="companyId" value={selected.id} />
            <label>ประเภท
              <select name="contactType"><option value="CUSTOMER">ลูกค้า</option><option value="VENDOR">คู่ค้า</option><option value="BOTH">ทั้งสอง</option></select>
            </label>
            <label>ชื่อแสดง<input name="displayName" required maxLength={160} /></label>
            <label>ชื่อนิติบุคคล<input name="legalName" maxLength={200} /></label>
            <label>เลขประจำตัวผู้เสียภาษี<input name="taxId" maxLength={30} /></label>
            <label>อีเมล<input name="email" type="email" /></label>
            <label>โทรศัพท์<input name="phone" /></label>
            <button className="primaryBtn" type="submit">เพิ่ม Contact</button>
          </form>
        </article>
        <article className="panel">
          <h3>รายการ ({contacts.length})</h3>
          <div className="accountList">
            {contacts.map((c: any) => <div className="accountRow" key={c.id}><div className="accountIcon">👤</div><div className="grow"><b>{c.display_name}</b><span>{c.contact_type} · Tax ID {c.tax_id ?? '-'}</span></div><div className="right"><span>{c.email ?? ''}</span><span>{c.phone ?? ''}</span></div></div>)}
          </div>
        </article>
      </section>
    </AppShell>
  );
}

import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { getMembership, listCompaniesForUser, listMemberships } from '@accounting-os/db';

export default async function AccessPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const [rows, mine] = await Promise.all([listMemberships(selected.id), getMembership(user.id, selected.id)]);
  const canEdit = mine?.role === 'OWNER';

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead"><div><p className="eyebrow">ACCESS CONTROL</p><h1>พนักงานและสิทธิ์</h1><p className="muted">AI ของพนักงานแต่ละคนต้องมีสิทธิ์ไม่เกินสิทธิ์ของพนักงานคนนั้น</p></div></div>
      {params.ok ? <div className="successBox">อัปเดตสิทธิ์แล้ว</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}
      {canEdit ? (
        <section className="panel accessCreate">
          <h3>เพิ่มพนักงาน / ผูกพนักงานกับบริษัท</h3>
          <form className="employeeCreate" action="/api/access/create" method="post">
            <input type="hidden" name="companyId" value={selected.id} />
            <label>ชื่อ<input name="displayName" required minLength={2} /></label>
            <label>อีเมล<input name="email" type="email" required /></label>
            <label>Temporary password<input name="temporaryPassword" type="password" minLength={12} required /></label>
            <label>Role
              <select name="role" defaultValue="ACCOUNTANT">
                {['CFO','ACCOUNTING_MANAGER','ACCOUNTANT','STAFF','AUDITOR'].map(r => <option key={r}>{r}</option>)}
              </select>
            </label>
            <button className="primaryBtn" type="submit">เพิ่มพนักงาน</button>
          </form>
          <p className="muted">ผู้ใช้ใหม่จะถูกบังคับให้เปลี่ยน temporary password หลัง login ครั้งแรก</p>
        </section>
      ) : null}

      <section className="panel recent">
        {rows.map((m: any) => (
          <form className="permissionRow" action="/api/access/update" method="post" key={m.user_id}>
            <input type="hidden" name="companyId" value={selected.id} />
            <input type="hidden" name="userId" value={m.user_id} />
            <div><b>{m.display_name}</b><span>{m.email}</span></div>
            <label>Role
              <select name="role" defaultValue={m.role} disabled={!canEdit}>
                {['OWNER','CFO','ACCOUNTING_MANAGER','ACCOUNTANT','STAFF','AUDITOR'].map(r => <option key={r}>{r}</option>)}
              </select>
            </label>
            {[
              ['canRead','Read',m.can_read],
              ['canCreateDraft','Draft',m.can_create_draft],
              ['canApprove','Approve',m.can_approve],
              ['canPost','Post',m.can_post],
            ].map(([name,label,value]: any) => <label className="checkLabel" key={name}><input type="checkbox" name={name} defaultChecked={value} disabled={!canEdit}/>{label}</label>)}
            <label>Limit<input name="approvalLimit" type="number" min="0" step="0.01" defaultValue={m.approval_limit ?? ''} disabled={!canEdit}/></label>
            {canEdit ? <button className="smallBtn" type="submit">บันทึก</button> : null}
          </form>
        ))}
      </section>
    </AppShell>
  );
}

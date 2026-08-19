import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { listAuditEvents, listCompaniesForUser } from '@accounting-os/db';

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const events = await listAuditEvents(selected.id, 150);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead">
        <div>
          <p className="eyebrow">APPEND-ONLY AUDIT</p>
          <h1>Audit Log</h1>
          <p className="muted">ดูว่าใครทำอะไรกับบริษัทนี้ ย้อนหลังจาก event ledger</p>
        </div>
      </div>
      <section className="panel">
        <div className="auditTable">
          <div className="auditRow auditHead">
            <span>เวลา</span><span>เหตุการณ์</span><span>ผู้กระทำ</span><span>Resource</span><span>รายละเอียด</span>
          </div>
          {events.map((e: any) => (
            <div className="auditRow" key={e.id}>
              <span>{new Date(e.occurred_at).toLocaleString('th-TH')}</span>
              <b>{e.event_type}</b>
              <span>{e.actor_name ?? 'SYSTEM'}<small>{e.actor_email ?? ''}</small></span>
              <span>{e.resource_type}<small>{e.resource_id ?? ''}</small></span>
              <code>{JSON.stringify(e.payload)}</code>
            </div>
          ))}
        </div>
      </section>
    </AppShell>
  );
}

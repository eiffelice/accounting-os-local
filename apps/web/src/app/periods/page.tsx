import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { getMembership, listCompaniesForUser, listFiscalPeriods } from '@accounting-os/db';

export default async function PeriodsPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const [periods, membership] = await Promise.all([
    listFiscalPeriods(selected.id),
    getMembership(user.id, selected.id),
  ]);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead"><div><p className="eyebrow">PERIOD CONTROL</p><h1>รอบบัญชี</h1><p className="muted">ปิดงวดไม่ได้ถ้ายังมี Draft ในช่วงนั้น</p></div></div>
      {params.ok ? <div className="successBox">{params.ok}</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}
      <section className="panel">
        {periods.map((p: any) => (
          <div className="approvalRow" key={p.id}>
            <div><b>{p.period_key}</b><span>{String(p.start_date).slice(0,10)} → {String(p.end_date).slice(0,10)}</span></div>
            <strong className={p.status === 'OPEN' ? 'posted' : 'draftText'}>{p.status}</strong>
            <div className="approvalActions">
              {p.status === 'OPEN' && membership?.can_approve ? (
                <form action="/api/periods/close" method="post">
                  <input type="hidden" name="companyId" value={selected.id} />
                  <input type="hidden" name="periodId" value={p.id} />
                  <input type="hidden" name="reason" value="Closed from local UI" />
                  <button className="dangerBtn" type="submit">ปิดงวด</button>
                </form>
              ) : null}
              {p.status === 'CLOSED' && ['OWNER','CFO'].includes(membership?.role ?? '') ? (
                <form action="/api/periods/reopen" method="post">
                  <input type="hidden" name="companyId" value={selected.id} />
                  <input type="hidden" name="periodId" value={p.id} />
                  <input type="hidden" name="reason" value="Reopened from local UI" />
                  <button className="smallBtn" type="submit">เปิดงวดใหม่</button>
                </form>
              ) : null}
            </div>
          </div>
        ))}
      </section>
    </AppShell>
  );
}

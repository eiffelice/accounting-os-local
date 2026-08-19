import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { listApprovals, listCompaniesForUser, getMembership } from '@accounting-os/db';

const money = (v: number | string | null) =>
  v == null ? '-' : new Intl.NumberFormat('th-TH', { style: 'currency', currency: 'THB' }).format(Number(v));

export default async function ApprovalsPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const [items, membership] = await Promise.all([
    listApprovals(selected.id),
    getMembership(user.id, selected.id),
  ]);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead"><div><p className="eyebrow">MAKER → CHECKER → POSTER</p><h1>Approval Inbox</h1><p className="muted">Approve ก่อน แล้วผู้มี can_post จึง Post Ledger ได้</p></div></div>
      {params.ok ? <div className="successBox">{params.ok}</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}

      <section className="panel">
        {items.length === 0 ? <div className="emptyState">ไม่มีรายการรออนุมัติ</div> : items.map((x: any) => (
          <div className="approvalRow" key={x.id}>
            <div>
              <b>{x.memo ?? x.action}</b>
              <span>{x.txn_date ? String(x.txn_date).slice(0,10) : ''} · {x.source_type} · โดย {x.requested_by_name}</span>
            </div>
            <div><strong>{money(x.amount)}</strong><span className={x.status === 'APPROVED' ? 'posted' : 'draftText'}>{x.status}</span></div>
            <div className="approvalActions">
              {x.status === 'PENDING' && membership?.can_approve ? (
                <>
                  <form action="/api/approvals/approve" method="post">
                    <input type="hidden" name="companyId" value={selected.id} />
                    <input type="hidden" name="requestId" value={x.id} />
                    <input type="hidden" name="reason" value="Reviewed in local UI" />
                    <button className="successBtn" type="submit">อนุมัติ</button>
                  </form>
                  <form action="/api/approvals/reject" method="post">
                    <input type="hidden" name="companyId" value={selected.id} />
                    <input type="hidden" name="requestId" value={x.id} />
                    <input type="hidden" name="reason" value="Rejected in local UI" />
                    <button className="dangerBtn" type="submit">ปฏิเสธ</button>
                  </form>
                </>
              ) : <span className="muted">ไม่มีสิทธิ์ Approve</span>}
              {x.status === 'APPROVED' && x.journal_status === 'DRAFT' && membership?.can_post ? (
                <form action="/api/approvals/post" method="post">
                  <input type="hidden" name="companyId" value={selected.id} />
                  <input type="hidden" name="entryId" value={x.resource_id} />
                  <button className="primaryBtn small" type="submit">Post ถ้าอนุมัติแล้ว</button>
                </form>
              ) : null}
            </div>
          </div>
        ))}
      </section>
    </AppShell>
  );
}

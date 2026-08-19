import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import {
  listCompaniesForUser,
  listExpenseAccounts,
  listFinancialAccounts,
  listRevenueAccounts,
  recentJournals,
} from '@accounting-os/db';

export default async function TransactionsPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  if (!selected) return <AppShell user={user}><div className="panel">ไม่มีบริษัท</div></AppShell>;

  const [accounts, expenses, revenues, journals] = await Promise.all([
    listFinancialAccounts(selected.id),
    listExpenseAccounts(selected.id),
    listRevenueAccounts(selected.id),
    recentJournals(selected.id, 15),
  ]);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <div className="pageHead">
        <div><p className="eyebrow">HUMAN ENTRY</p><h1>รายรับ / รายจ่าย</h1><p className="muted">ทุกการบันทึกจะเริ่มเป็น Draft และเข้า Approval Inbox</p></div>
      </div>

      {params.ok ? <div className="successBox">สร้าง Draft แล้ว และส่งเข้าคิวอนุมัติ</div> : null}
      {params.error ? <div className="errorBox">สร้างรายการไม่สำเร็จ: {params.error}</div> : null}

      <section className="grid">
        <article className="panel">
          <h3>บันทึกรายจ่าย</h3>
          <form className="formStack" action="/api/transactions/expense" method="post">
            <input type="hidden" name="companyId" value={selected.id} />
            <label>วันที่<input type="date" name="txnDate" required /></label>
            <label>บัญชีที่จ่าย
              <select name="financialAccountId" required>{accounts.map((a: any) => <option key={a.id} value={a.id}>{a.name} ({a.masked_number ?? a.kind})</option>)}</select>
            </label>
            <label>หมวดค่าใช้จ่าย
              <select name="accountCode" required>{expenses.map((a: any) => <option key={a.id} value={a.code}>{a.code} — {a.name_th}</option>)}</select>
            </label>
            <label>จำนวนเงิน<input name="amount" type="number" min="0.01" step="0.01" required /></label>
            <label>รายละเอียด<input name="description" maxLength={500} required /></label>
            <button className="primaryBtn" type="submit">สร้าง Expense Draft</button>
          </form>
        </article>

        <article className="panel">
          <h3>บันทึกรายรับ</h3>
          <form className="formStack" action="/api/transactions/income" method="post">
            <input type="hidden" name="companyId" value={selected.id} />
            <label>วันที่<input type="date" name="txnDate" required /></label>
            <label>บัญชีที่รับเงิน
              <select name="financialAccountId" required>{accounts.map((a: any) => <option key={a.id} value={a.id}>{a.name} ({a.masked_number ?? a.kind})</option>)}</select>
            </label>
            <label>หมวดรายได้
              <select name="accountCode" required>{revenues.map((a: any) => <option key={a.id} value={a.code}>{a.code} — {a.name_th}</option>)}</select>
            </label>
            <label>จำนวนเงิน<input name="amount" type="number" min="0.01" step="0.01" required /></label>
            <label>รายละเอียด<input name="description" maxLength={500} required /></label>
            <button className="primaryBtn" type="submit">สร้าง Income Draft</button>
          </form>
        </article>
      </section>

      <section className="panel recent">
        <h3>Journal ล่าสุด</h3>
        <div className="table">
          <div className="tr th"><span>วันที่</span><span>เลขที่</span><span>รายละเอียด</span><span>สถานะ</span></div>
          {journals.map((j: any) => <div className="tr" key={j.id}><span>{String(j.txn_date).slice(0,10)}</span><span>{j.entry_no ?? 'DRAFT'}</span><span>{j.memo}</span><span>{j.status}</span></div>)}
        </div>
      </section>
    </AppShell>
  );
}

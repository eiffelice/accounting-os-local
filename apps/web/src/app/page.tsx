import {
  dashboardSummary,
  listCompaniesForUser,
  listFinancialAccounts,
  recentJournals,
} from '@accounting-os/db';
import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import { formatThaiDate, formatThb } from '@/lib/format';
import { BankLogo } from '@/components/bank-logo';

export const dynamic = 'force-dynamic';

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ company?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];

  if (!selected) {
    return <AppShell user={user}><div className="panel">ยังไม่มีบริษัทที่คุณเข้าถึงได้</div></AppShell>;
  }

  const [summary, accounts, journals] = await Promise.all([
    dashboardSummary(selected.id),
    listFinancialAccounts(selected.id),
    recentJournals(selected.id, 8),
  ]);

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <header className="topbar">
        <div>
          <p className="eyebrow">บริษัทที่กำลังดู</p>
          <h1>{selected.display_name}</h1>
        </div>
        <div className="companySwitch">
          {companies.map((c) => (
            <a key={c.id}
              className={c.id === selected.id ? 'company activeCompany' : 'company'}
              href={`/?company=${c.id}`}>
              {c.code}
            </a>
          ))}
        </div>
      </header>

      <section className="hero">
        <div>
          <span className="pill">Canonical Ledger • Thai Tax Core • Local Only</span>
          <h2>Accounting OS v0.3</h2>
          <p>หลายบริษัท • หลายบัญชี • Human Approval • VAT/WHT Deterministic • MCP Safe Tools</p>
        </div>
        <div className="health">
          <span>Ledger Integrity</span><b>ENFORCED</b>
          <span>Tax Rule Versioning</span><b>ENABLED</b>
          <span>AI Tax Filing</span><b>DISABLED</b>
        </div>
      </section>

      <section className="kpis">
        <article className="card"><span>รายรับสะสม</span><strong>{formatThb(summary.revenue)}</strong><small>Posted Ledger</small></article>
        <article className="card"><span>รายจ่ายสะสม</span><strong>{formatThb(summary.expense)}</strong><small>Posted Ledger</small></article>
        <article className="card"><span>กำไรเบื้องต้น</span><strong>{formatThb(summary.profit)}</strong><small>Revenue - Expense</small></article>
        <article className="card"><span>เงินสด / ธนาคาร</span><strong>{formatThb(summary.cash_balance)}</strong><small>{accounts.length} บัญชี</small></article>
      </section>

      <section className="grid">
        <article className="panel">
          <div className="panelHead"><div><p className="eyebrow">FINANCIAL ACCOUNTS</p><h3>หลายบัญชีในบริษัทเดียว</h3></div><span className="count">{accounts.length}</span></div>
          <div className="accountList">
            {accounts.map((a: any) => (
              <div className="accountRow" key={a.id}>
                <BankLogo slug={a.bank_slug} color={a.bank_brand_color} name={a.bank_name} kind={a.kind}/>
                <div className="grow"><b>{a.name}</b><span>{a.bank_name ?? a.institution ?? 'เงินสด'} · {a.masked_number ?? 'Local cash'}</span></div>
                <div className="right"><b>{a.currency}</b><span>GL {a.gl_code}</span></div>
              </div>
            ))}
          </div>
        </article>

        <article className="panel" id="mcp">
          <div className="panelHead"><div><p className="eyebrow">MCP CONTROL</p><h3>AI = Read / Calculate / Draft</h3></div><span className="statusGood">LOCAL STDIO</span></div>
          {[
            ['company_list','READ'],
            ['financial_account_list','READ'],
            ['report_trial_balance','READ'],
            ['journal_recent','READ'],
            ['expense_create_draft','DRAFT'],
            ['tax_rule_list','READ'],
            ['tax_calculate_vat','CALC'],
            ['tax_calculate_wht','CALC'],
            ['tax_calendar_month','READ'],
          ].map(([tool, level]) => (
            <div className="tool" key={tool}><code>{tool}</code><span className={level === 'DRAFT' ? 'draft' : 'allow'}>{level}</span></div>
          ))}
          <div className="tool denied"><code>journal_post</code><span>HUMAN UI ONLY</span></div>
          <div className="tool denied"><code>tax_submit</code><span>NOT EXPOSED</span></div>
          <div className="tool denied"><code>payment_execute</code><span>NOT EXPOSED</span></div>
        </article>
      </section>

      <section className="panel recent">
        <div className="panelHead"><div><p className="eyebrow">CANONICAL LEDGER</p><h3>รายการล่าสุด</h3></div></div>
        <div className="table">
          <div className="tr th"><span>วันที่</span><span>เลขที่</span><span>รายละเอียด</span><span>สถานะ</span></div>
          {journals.map((j: any) => (
            <div className="tr" key={j.id}>
              <span>{formatThaiDate(String(j.txn_date).slice(0, 10))}</span>
              <span>{j.entry_no ?? 'DRAFT'}</span>
              <span className="journalDescription">
                <BankLogo slug={j.bank_slug} color={j.bank_brand_color} name={j.bank_name} kind={j.financial_account_kind} small/>
                <span><b>{j.memo}</b><small>{j.financial_account_name ?? 'Manual journal'}</small></span>
              </span>
              <span><b className={j.status === 'POSTED' ? 'posted' : 'draftText'}>{j.status}</b></span>
            </div>
          ))}
        </div>
      </section>
    </AppShell>
  );
}

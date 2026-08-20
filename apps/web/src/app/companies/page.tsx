import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import {
  financialAccountBalances,
  listBanks,
  listCompaniesForUser,
} from '@accounting-os/db';
import { formatThb } from '@/lib/format';
import { BankLogo } from '@/components/bank-logo';
import { FinancialAccountForm } from '@/components/financial-account-form';

export default async function CompaniesPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  const [balances, banks] = await Promise.all([
    selected ? financialAccountBalances(selected.id) : [],
    listBanks(),
  ]);

  return (
    <AppShell user={user} selectedCompanyId={selected?.id}>
      <div className="pageHead">
        <div>
          <p className="eyebrow">MULTI-COMPANY / MULTI-ACCOUNT</p>
          <h1>บริษัทและบัญชีการเงิน</h1>
          <p className="muted">เพิ่มบริษัทได้หลายแห่ง และแต่ละบริษัทมีบัญชีธนาคาร/เงินสด/อีวอลเล็ต/บัตรเครดิตได้หลายบัญชี</p>
        </div>
      </div>

      {params.ok ? <div className="successBox">{params.ok}</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}

      <section className="grid">
        <article className="panel">
          <h3>เพิ่มบริษัท</h3>
          <form className="formStack" action="/api/companies/create" method="post">
            <label>รหัสบริษัท<input name="code" placeholder="COMP-C" required maxLength={30}/></label>
            <label>ชื่อแสดง<input name="displayName" required maxLength={160}/></label>
            <label>ชื่อจดทะเบียน<input name="legalName" required maxLength={200}/></label>
            <label>เลขผู้เสียภาษี<input name="taxId" maxLength={30}/></label>
            <button className="primaryBtn" type="submit">สร้างบริษัทใหม่</button>
          </form>
        </article>

        <article className="panel">
          <h3>บริษัททั้งหมด ({companies.length})</h3>
          <div className="accountList">
            {companies.map(c => (
              <a className="accountRow" href={`/companies?company=${c.id}`} key={c.id}>
                <div className="accountIcon">🏢</div>
                <div className="grow"><b>{c.display_name}</b><span>{c.code} · {c.legal_name}</span></div>
                <div className="right"><span>{c.base_currency}</span></div>
              </a>
            ))}
          </div>
        </article>
      </section>

      {selected ? (
        <section className="grid recent">
          <article className="panel">
            <h3>เพิ่มบัญชี — {selected.display_name}</h3>
            <FinancialAccountForm companyId={selected.id} banks={banks}/>
          </article>

          <article className="panel">
            <h3>ยอดแยกแต่ละบัญชี</h3>
            <div className="accountList">
              {balances.map((a: any) => (
                <div className="accountRow" key={a.id}>
                  <BankLogo slug={a.bank_slug} color={a.bank_brand_color} name={a.bank_name} kind={a.kind}/>
                  <div className="grow"><b>{a.name}</b><span>{a.bank_name ?? a.institution ?? a.kind} · {a.masked_number ?? '-'}</span></div>
                  <div className="right"><b>{formatThb(a.balance)}</b><span>{a.currency}</span></div>
                </div>
              ))}
              {balances.length === 0 ? <div className="emptyState">ยังไม่มีบัญชี</div> : null}
            </div>
          </article>
        </section>
      ) : null}
    </AppShell>
  );
}

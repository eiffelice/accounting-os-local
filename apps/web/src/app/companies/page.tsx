import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';
import {
  financialAccountBalances,
  listCompaniesForUser,
} from '@accounting-os/db';
import { formatThb } from '@/lib/format';

export default async function CompaniesPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; ok?: string; error?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];
  const balances = selected ? await financialAccountBalances(selected.id) : [];

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
            <form className="formStack" action="/api/companies/account" method="post">
              <input type="hidden" name="companyId" value={selected.id}/>
              <label>ประเภท
                <select name="kind">
                  <option value="BANK">ธนาคาร</option>
                  <option value="CASH">เงินสด</option>
                  <option value="E_WALLET">E-Wallet</option>
                  <option value="CREDIT_CARD">บัตรเครดิต</option>
                </select>
              </label>
              <label>ชื่อบัญชี<input name="name" required maxLength={160}/></label>
              <label>ธนาคาร/สถาบัน<input name="institution" maxLength={120}/></label>
              <label>เลขที่ Mask แล้ว<input name="maskedNumber" placeholder="XXX-X-X1234-X" maxLength={80}/></label>
              <button className="primaryBtn" type="submit">เพิ่มบัญชี</button>
            </form>
          </article>

          <article className="panel">
            <h3>ยอดแยกแต่ละบัญชี</h3>
            <div className="accountList">
              {balances.map((a: any) => (
                <div className="accountRow" key={a.id}>
                  <div className="accountIcon">{a.kind === 'CASH' ? '฿' : '🏦'}</div>
                  <div className="grow"><b>{a.name}</b><span>{a.institution ?? a.kind} · {a.masked_number ?? '-'}</span></div>
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

import {
  getCompanyTaxProfile,
  listCompaniesForUser,
  listTaxRules,
  taxCalendarForPeriod,
  taxDashboard,
} from '@accounting-os/db';
import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';

export const dynamic = 'force-dynamic';

function rate(bps: number) {
  return `${(bps / 100).toFixed(2).replace(/\.00$/, '')}%`;
}

function bangkokDateParts() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const value = (type: string) => parts.find((p) => p.type === type)?.value;
  const today = `${value('year')}-${value('month')}-${value('day')}`;
  return { today, period: today.slice(0, 7) };
}

export default async function TaxPage({
  searchParams,
}: {
  searchParams: Promise<{ company?: string; period?: string }>;
}) {
  const user = await requireUser();
  const params = await searchParams;
  const companies = await listCompaniesForUser(user.id);
  const selected = companies.find((c) => c.id === params.company) ?? companies[0];

  if (!selected) {
    return <AppShell user={user}><div className="panel">ยังไม่มีบริษัทที่คุณเข้าถึงได้</div></AppShell>;
  }

  const { today, period: defaultPeriod } = bangkokDateParts();
  const period = /^\d{4}-\d{2}$/.test(params.period ?? '') ? params.period! : defaultPeriod;

  const [rules, calendar, profile, summary] = await Promise.all([
    listTaxRules({ asOf: today }),
    taxCalendarForPeriod(period),
    getCompanyTaxProfile(user.id, selected.id),
    taxDashboard(user.id, selected.id, period),
  ]);

  const vatRule = rules.find((r) => r.tax_type === 'VAT' && r.rule_code === 'VAT_STANDARD');
  const whtRules = rules.filter((r) => r.tax_type === 'WHT');

  return (
    <AppShell user={user} selectedCompanyId={selected.id}>
      <header className="topbar">
        <div>
          <p className="eyebrow">THAI TAX CORE</p>
          <h1>ภาษี — {selected.display_name}</h1>
        </div>
        <div className="companySwitch">
          {companies.map((c) => (
            <a
              key={c.id}
              className={c.id === selected.id ? 'company activeCompany' : 'company'}
              href={`/tax?company=${c.id}&period=${period}`}
            >
              {c.code}
            </a>
          ))}
        </div>
      </header>

      <section className="hero">
        <div>
          <span className="pill">Rule Versioning • Deterministic • Provenance</span>
          <h2>Accounting OS v0.3 — Thai Tax Core</h2>
          <p>VAT • WHT • Effective Date • Official Source • Base Tax Calendar</p>
        </div>
        <div className="health">
          <span>VAT Registered</span><b>{profile?.vat_registered ? 'YES' : 'NO / NOT SET'}</b>
          <span>Filing Channel</span><b>{profile?.filing_channel ?? 'INTERNET'}</b>
          <span>AI Tax Filing</span><b>DISABLED</b>
        </div>
      </section>

      <section className="kpis">
        <article className="card">
          <span>VAT อัตราปัจจุบัน</span>
          <strong>{vatRule ? rate(vatRule.rate_bps) : 'ไม่มี Rule'}</strong>
          <small>{vatRule ? `${vatRule.effective_from} → ${vatRule.effective_to ?? 'open'}` : 'ต้องตรวจ Tax Rule Registry'}</small>
        </article>
        <article className="card">
          <span>WHT Rules ที่ active</span>
          <strong>{whtRules.length}</strong>
          <small>บริการ / เช่า / โฆษณา</small>
        </article>
        <article className="card">
          <span>Tax Period</span>
          <strong>{period}</strong>
          <small>วันยื่นจริงต้องตรวจปฏิทินกรมสรรพากร</small>
        </article>
        <article className="card">
          <span>FINAL Tax Calculations</span>
          <strong>{summary.reduce((n: number, x: any) => n + Number(x.calculations), 0)}</strong>
          <small>บันทึกที่ล็อกแล้ว</small>
        </article>
      </section>

      <section className="grid">
        <article className="panel">
          <div className="panelHead"><div><p className="eyebrow">TAX RULE REGISTRY</p><h3>กฎที่ใช้ ณ วันที่ {today}</h3></div></div>
          <div className="accountList">
            {rules.map((r) => (
              <div className="accountRow" key={r.id}>
                <div className="accountIcon">{r.tax_type === 'VAT' ? 'V' : 'W'}</div>
                <div className="grow">
                  <b>{r.name_th}</b>
                  <span>{r.rule_code} v{r.version} · {r.legal_reference}</span>
                </div>
                <div className="right">
                  <b>{rate(r.rate_bps)}</b>
                  <span>{r.verification_status}</span>
                </div>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panelHead"><div><p className="eyebrow">BASE TAX CALENDAR</p><h3>กำหนดฐานของรอบ {period}</h3></div></div>
          {calendar.map((c) => (
            <div className="tool" key={c.rule_code}>
              <div>
                <code>{c.form_codes.join(', ')}</code>
                <div><small>กระดาษ {c.paperBaseDueDate ?? '-'} · ออนไลน์ {c.internetBaseDueDate ?? '-'}</small></div>
              </div>
              <span className="draft">VERIFY</span>
            </div>
          ))}
          <p className="muted">วันข้างต้นเป็น base schedule เท่านั้น วันหยุด/ประกาศขยายเวลาอาจทำให้วันยื่นจริงเปลี่ยน ต้องตรวจปฏิทินกรมสรรพากรก่อนยื่นทุกครั้ง</p>
        </article>
      </section>

      <section className="panel recent">
        <div className="panelHead"><div><p className="eyebrow">SAFETY</p><h3>ขอบเขต v0.3</h3></div></div>
        <div className="table">
          <div className="tr th"><span>ความสามารถ</span><span>สถานะ</span><span>หลักการ</span><span>การยืนยัน</span></div>
          <div className="tr"><span>คำนวณ VAT</span><span><b className="posted">ENABLED</b></span><span>Postgres NUMERIC</span><span>Rule version + source</span></div>
          <div className="tr"><span>คำนวณ WHT</span><span><b className="posted">ENABLED</b></span><span>จำแนกประเภทธุรกรรม</span><span>ตรวจข้อยกเว้นก่อนยื่น</span></div>
          <div className="tr"><span>AI ยื่นภาษี</span><span><b className="draftText">DISABLED</b></span><span>Human-only</span><span>ยังไม่ expose ผ่าน MCP</span></div>
        </div>
      </section>
    </AppShell>
  );
}

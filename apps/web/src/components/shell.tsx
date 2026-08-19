import Link from 'next/link';
import { listCompaniesForUser } from '@accounting-os/db';
import type { LocalUser } from '@accounting-os/db';

export async function AppShell({
  user,
  selectedCompanyId,
  children,
}: {
  user: LocalUser;
  selectedCompanyId?: string;
  children: React.ReactNode;
}) {
  const companies = await listCompaniesForUser(user.id);
  const selected =
    companies.find((c) => c.id === selectedCompanyId) ?? companies[0];

  const q = selected ? `?company=${selected.id}` : '';

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="logo">A</div>
          <div>
            <strong>Accounting OS</strong>
            <small>LOCAL v0.2</small>
          </div>
        </div>

        <nav>
          <Link className="nav" href={`/${q}`}>ภาพรวม</Link>
          <Link className="nav" href={`/companies${q}`}>บริษัท / บัญชี</Link>
          <Link className="nav" href={`/transactions${q}`}>รายรับ / รายจ่าย</Link>
          <Link className="nav" href={`/approvals${q}`}>อนุมัติ</Link>
          <Link className="nav" href={`/contacts${q}`}>ลูกค้า / คู่ค้า</Link>
          <Link className="nav" href={`/periods${q}`}>รอบบัญชี</Link>
          <Link className="nav" href={`/documents${q}`}>เอกสาร Local</Link>
          <Link className="nav" href={`/access${q}`}>พนักงานและสิทธิ์</Link>
          <Link className="nav" href={`/audit${q}`}>Audit Log</Link>
          <Link className="nav" href="/profile">บัญชีผู้ใช้</Link>
          <Link className="nav" href={`/${q}#mcp`}>AI / MCP</Link>
        </nav>

        <div className="localCard">
          <b>{user.display_name}</b>
          <span>{user.email}</span>
          <span className="safe">● Local session</span>
          <form action="/api/logout" method="post">
            <button className="smallBtn" type="submit">ออกจากระบบ</button>
          </form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}

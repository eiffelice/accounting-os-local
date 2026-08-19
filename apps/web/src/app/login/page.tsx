import { currentUser } from '@/lib/auth';
import { redirect } from 'next/navigation';

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  if (await currentUser()) redirect('/');
  const params = await searchParams;

  return (
    <main className="loginWrap">
      <section className="loginCard">
        <div className="logo bigLogo">A</div>
        <p className="eyebrow">ACCOUNTING OS LOCAL</p>
        <h1>เข้าสู่ระบบ</h1>
        <p className="muted">ข้อมูลบัญชีและ session อยู่ในเครื่องของคุณ</p>

        {params.error ? <div className="errorBox">อีเมลหรือรหัสผ่านไม่ถูกต้อง</div> : null}

        <form className="formStack" action="/api/login" method="post">
          <label>
            อีเมล
            <input name="email" type="email" defaultValue="owner@local.accounting" required />
          </label>
          <label>
            รหัสผ่าน
            <input name="password" type="password" defaultValue="change-me-now" required />
          </label>
          <button className="primaryBtn" type="submit">เข้าสู่ระบบ Local</button>
        </form>
        <small className="warnText">Demo: เปลี่ยนรหัสผ่านก่อนใช้ข้อมูลจริง</small>
      </section>
    </main>
  );
}

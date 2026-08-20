import { requireUser } from '@/lib/auth';
import { AppShell } from '@/components/shell';

export default async function ProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string; mustChange?: string }>;
}) {
  const user = await requireUser({ allowMustChangePassword: true });
  const params = await searchParams;
  return (
    <AppShell user={user}>
      <div className="pageHead"><div><p className="eyebrow">LOCAL SECURITY</p><h1>บัญชีผู้ใช้</h1></div></div>
      {params.mustChange ? <div className="errorBox">บัญชีนี้ใช้รหัสผ่านชั่วคราว กรุณาเปลี่ยนรหัสผ่านก่อนใช้งานข้อมูลจริง</div> : null}
      {params.ok ? <div className="successBox">เปลี่ยนรหัสผ่านแล้ว กรุณาเข้าสู่ระบบใหม่</div> : null}
      {params.error ? <div className="errorBox">{params.error}</div> : null}
      <section className="panel narrowPanel">
        <h3>{user.display_name}</h3>
        <p className="muted">{user.email}</p>
        <form className="formStack" action="/api/profile/password" method="post">
          <label>รหัสผ่านปัจจุบัน<input name="currentPassword" type="password" required/></label>
          <label>รหัสผ่านใหม่ (อย่างน้อย 12 ตัว)<input name="newPassword" type="password" minLength={12} required/></label>
          <label>ยืนยันรหัสผ่านใหม่<input name="confirmPassword" type="password" minLength={12} required/></label>
          <button className="primaryBtn" type="submit">เปลี่ยนรหัสผ่าน</button>
        </form>
      </section>
    </AppShell>
  );
}

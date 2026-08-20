import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { getSessionUser } from '@accounting-os/db';

export const SESSION_COOKIE = 'aos_session';

export async function currentUser(options?: { allowMustChangePassword?: boolean }) {
  const store = await cookies();
  const user = await getSessionUser(store.get(SESSION_COOKIE)?.value);
  if (user?.must_change_password && !options?.allowMustChangePassword) return null;
  return user;
}

export async function requireUser(options?: { allowMustChangePassword?: boolean }) {
  const user = await currentUser({ allowMustChangePassword: true });
  if (!user) redirect('/login');
  if (user.must_change_password && !options?.allowMustChangePassword) {
    redirect('/profile?mustChange=1');
  }
  return user;
}

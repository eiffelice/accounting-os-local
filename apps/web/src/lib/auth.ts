import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { getSessionUser } from '@accounting-os/db';

export const SESSION_COOKIE = 'aos_session';

export async function currentUser() {
  const store = await cookies();
  return getSessionUser(store.get(SESSION_COOKIE)?.value);
}

export async function requireUser() {
  const user = await currentUser();
  if (!user) redirect('/login');
  return user;
}

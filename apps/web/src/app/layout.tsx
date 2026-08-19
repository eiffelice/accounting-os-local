import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Accounting OS Local',
  description: 'Local-first multi-company accounting foundation',
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="th">
      <body>{children}</body>
    </html>
  );
}

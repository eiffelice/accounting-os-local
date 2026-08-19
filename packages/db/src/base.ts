import pg from 'pg';

const { Pool } = pg;

export const pool = new Pool({
  connectionString:
    process.env.DATABASE_URL ??
    'postgresql://accounting:accounting_local_only@127.0.0.1:5432/accounting_os',
  max: 10,
});

export type Company = {
  id: string;
  code: string;
  legal_name: string;
  display_name: string;
  base_currency: string;
};

export type LocalUser = {
  id: string;
  email: string;
  display_name: string;
  is_active: boolean;
};

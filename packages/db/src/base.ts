import pg from 'pg';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
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

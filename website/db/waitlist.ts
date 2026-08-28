import { Pool } from 'pg';

export type WaitlistResult = { alreadyJoined: boolean };

const globalForDatabase = globalThis as unknown as { pesuPool?: Pool };

function getPool() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('Waitlist storage is unavailable.');

  if (!globalForDatabase.pesuPool) {
    globalForDatabase.pesuPool = new Pool({
      connectionString,
      max: 3,
      idleTimeoutMillis: 20_000,
      connectionTimeoutMillis: 8_000,
    });
  }

  return globalForDatabase.pesuPool;
}

export async function joinWaitlist(rawEmail: string): Promise<WaitlistResult> {
  const email = rawEmail.trim().toLowerCase();
  const result = await getPool().query<{ id: number }>(
    `INSERT INTO waitlist (email)
     VALUES ($1)
     ON CONFLICT (email) DO NOTHING
     RETURNING id`,
    [email],
  );

  return { alreadyJoined: result.rowCount === 0 };
}

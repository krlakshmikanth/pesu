import { joinWaitlist } from '@/db/waitlist';

export const runtime = 'nodejs';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function POST(request: Request) {
  try {
    const body = await request.json() as { email?: unknown; company?: unknown };

    // A filled hidden field is almost certainly an automated submission.
    if (typeof body.company === 'string' && body.company.trim()) {
      return Response.json({ alreadyJoined: false });
    }

    if (typeof body.email !== 'string') {
      return Response.json({ error: 'Enter your email address.' }, { status: 400 });
    }

    const email = body.email.trim().toLowerCase();
    if (email.length > 254 || !EMAIL_PATTERN.test(email)) {
      return Response.json({ error: 'Enter a valid email address.' }, { status: 400 });
    }

    const result = await joinWaitlist(email);
    return Response.json(result, { status: result.alreadyJoined ? 200 : 201 });
  } catch {
    return Response.json({ error: 'The waitlist is temporarily unavailable.' }, { status: 500 });
  }
}

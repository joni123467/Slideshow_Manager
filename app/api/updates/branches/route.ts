import { NextResponse } from 'next/server';
import { fetchVersionBranches } from '@/lib/versioning';

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const branches = await fetchVersionBranches();
    return NextResponse.json({ branches });
  } catch (error) {
    console.error('Failed to fetch version branches', error);
    return NextResponse.json(
      { error: 'Branch-Abfrage fehlgeschlagen. Bitte prüfen Sie die Repository-Konfiguration.' },
      { status: 500 }
    );
  }
}

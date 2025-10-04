import { NextRequest, NextResponse } from 'next/server';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fetchLatestVersionBranch, isVersionBranch } from '@/lib/versioning';

export const dynamic = 'force-dynamic';

async function ensureScriptExists(scriptPath: string) {
  try {
    await access(scriptPath);
  } catch {
    throw new Error(`Update-Skript nicht gefunden (${scriptPath}).`);
  }
}

async function runScript(scriptPath: string, branch: string): Promise<{ exitCode: number; output: string }> {
  await ensureScriptExists(scriptPath);
  return new Promise((resolve, reject) => {
    const child = spawn(scriptPath, ['--branch', branch], {
      cwd: process.cwd(),
      env: process.env,
      shell: false
    });
    let output = '';
    child.stdout.on('data', (chunk) => {
      output += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      output += chunk.toString();
    });
    child.on('error', (error) => {
      reject(error);
    });
    child.on('close', (code) => {
      resolve({ exitCode: code ?? 0, output });
    });
  });
}

export async function POST(request: NextRequest) {
  try {
    let selectedBranch: string | undefined;
    if (request.headers.get('content-type')?.includes('application/json')) {
      const body = await request.json();
      if (body?.branch) {
        selectedBranch = String(body.branch);
      }
    }

    if (selectedBranch && !isVersionBranch(selectedBranch)) {
      return NextResponse.json(
        { error: 'Ungültiger Branch-Name. Erwartet wird das Format version-x.x.x.' },
        { status: 400 }
      );
    }

    const branch = selectedBranch ?? (await fetchLatestVersionBranch());
    if (!branch) {
      return NextResponse.json(
        { error: 'Kein Version-Branch gefunden. Bitte Branch manuell angeben.' },
        { status: 400 }
      );
    }

    const scriptPath = path.join(process.cwd(), 'scripts', 'update.sh');
    const result = await runScript(scriptPath, branch);

    if (result.exitCode !== 0) {
      return NextResponse.json(
        { error: 'Update fehlgeschlagen.', branch, output: result.output.trim() },
        { status: 500 }
      );
    }

    return NextResponse.json({ branch, output: result.output.trim() });
  } catch (error) {
    console.error('Update execution failed', error);
    return NextResponse.json(
      { error: 'Update konnte nicht gestartet werden. Prüfen Sie die Server-Logs.' },
      { status: 500 }
    );
  }
}

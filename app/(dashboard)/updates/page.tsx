'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';

type BranchResponse = {
  branches?: string[];
  error?: string;
};

type UpdateResponse = {
  branch?: string;
  output?: string;
  error?: string;
};

function formatOutput(output?: string) {
  if (!output) {
    return 'Kein Ausgabelog verfügbar.';
  }
  return output
    .trim()
    .split('\n')
    .filter(Boolean)
    .join('\n');
}

export default function UpdatesPage() {
  const [branches, setBranches] = useState<string[]>([]);
  const [selectedBranch, setSelectedBranch] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState(false);
  const [result, setResult] = useState<UpdateResponse | null>(null);

  useEffect(() => {
    let isMounted = true;
    async function loadBranches() {
      setLoading(true);
      setError(null);
      try {
        const response = await fetch('/api/updates/branches', { cache: 'no-store' });
        const payload: BranchResponse = await response.json();
        if (!response.ok) {
          throw new Error(payload.error ?? 'Unbekannter Fehler beim Laden der Branches.');
        }
        if (!payload.branches || payload.branches.length === 0) {
          throw new Error('Keine Version-Branches gefunden.');
        }
        if (isMounted) {
          setBranches(payload.branches);
          setSelectedBranch(payload.branches[payload.branches.length - 1]);
        }
      } catch (err) {
        if (isMounted) {
          setError(err instanceof Error ? err.message : 'Branch-Liste konnte nicht geladen werden.');
        }
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    }
    loadBranches();
    return () => {
      isMounted = false;
    };
  }, []);

  const handleSubmit = useCallback(
    async (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      setUpdating(true);
      setResult(null);
      setError(null);
      try {
        const response = await fetch('/api/updates/run', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ branch: selectedBranch || undefined })
        });
        const payload: UpdateResponse = await response.json();
        if (!response.ok) {
          throw new Error(payload.error ?? 'Update fehlgeschlagen.');
        }
        setResult(payload);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Update konnte nicht gestartet werden.');
      } finally {
        setUpdating(false);
      }
    },
    [selectedBranch]
  );

  const statusMessage = useMemo(() => {
    if (updating) {
      return 'Update läuft...';
    }
    if (result?.branch) {
      return `Update auf ${result.branch} abgeschlossen.`;
    }
    return null;
  }, [result, updating]);

  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col gap-6 p-6">
      <header className="flex flex-col gap-2 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h1 className="text-3xl font-semibold">System Updates</h1>
          <p className="text-sm text-slate-400">
            Installiere neue Versionen der Slideshow Manager Anwendung direkt vom Server.
          </p>
        </div>
        <nav className="flex items-center gap-3 text-sm">
          <Link href="/dashboard" className="text-slate-300 hover:text-white">
            Dashboard
          </Link>
          <Link href="/updates" className="text-white">
            Updates
          </Link>
        </nav>
      </header>

      <section className="rounded-lg border border-slate-800 bg-slate-900 p-6">
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div>
            <label htmlFor="branch" className="block text-sm font-medium text-slate-200">
              Verfügbare Versionen
            </label>
            <select
              id="branch"
              name="branch"
              value={selectedBranch}
              onChange={(event) => setSelectedBranch(event.target.value)}
              className="mt-2 w-full rounded-md border border-slate-700 bg-slate-950 p-2 text-sm text-slate-100 focus:border-slate-500 focus:outline-none"
              disabled={loading || updating}
            >
              {branches.map((branch) => (
                <option key={branch} value={branch}>
                  {branch}
                </option>
              ))}
            </select>
            {loading && <p className="mt-2 text-xs text-slate-500">Branches werden geladen…</p>}
          </div>

          {error && <p className="text-sm text-red-400">{error}</p>}
          {statusMessage && !error && <p className="text-sm text-emerald-400">{statusMessage}</p>}

          <button
            type="submit"
            className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:cursor-not-allowed disabled:bg-emerald-800"
            disabled={loading || updating || branches.length === 0}
          >
            {updating ? 'Update wird ausgeführt…' : 'Update starten'}
          </button>
        </form>
      </section>

      <section className="rounded-lg border border-slate-800 bg-slate-900 p-6">
        <h2 className="text-lg font-semibold text-slate-100">Update-Protokoll</h2>
        <pre className="mt-3 max-h-72 overflow-auto whitespace-pre-wrap rounded-md bg-slate-950/60 p-3 text-xs text-slate-300">
          {formatOutput(result?.output)}
        </pre>
      </section>
    </main>
  );
}

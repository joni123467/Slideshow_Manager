const VERSION_BRANCH_PATTERN = /^version-(\d+)\.(\d+)\.(\d+)$/;

function ensureRepoIdentifier(): string {
  const repo = process.env.SLIDESHOW_MANAGER_REPO;
  if (!repo) {
    throw new Error('SLIDESHOW_MANAGER_REPO is not configured.');
  }
  return repo;
}

function getGithubBranchesUrl(repo: string): string {
  return `https://api.github.com/repos/${repo}/branches?per_page=100`;
}

function parseVersion(branch: string): [number, number, number] | null {
  const match = branch.match(VERSION_BRANCH_PATTERN);
  if (!match) {
    return null;
  }
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

export function isVersionBranch(branch: string): boolean {
  return VERSION_BRANCH_PATTERN.test(branch);
}

export function compareVersionBranches(a: string, b: string): number {
  const aParts = parseVersion(a);
  const bParts = parseVersion(b);
  if (!aParts && !bParts) {
    return 0;
  }
  if (!aParts) {
    return -1;
  }
  if (!bParts) {
    return 1;
  }
  for (let i = 0; i < aParts.length; i += 1) {
    if (aParts[i] !== bParts[i]) {
      return aParts[i] - bParts[i];
    }
  }
  return 0;
}

export async function fetchVersionBranches(): Promise<string[]> {
  const repo = ensureRepoIdentifier();
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'slideshow-manager'
  };
  if (process.env.SLIDESHOW_MANAGER_REPO_TOKEN) {
    headers.Authorization = `Bearer ${process.env.SLIDESHOW_MANAGER_REPO_TOKEN}`;
  }
  const response = await fetch(getGithubBranchesUrl(repo), {
    headers,
    cache: 'no-store'
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to load branches (${response.status}): ${body}`);
  }
  const data: Array<{ name: string }> = await response.json();
  return data
    .map((branch) => branch.name)
    .filter(isVersionBranch)
    .sort((a, b) => compareVersionBranches(a, b));
}

export async function fetchLatestVersionBranch(): Promise<string | null> {
  const branches = await fetchVersionBranches();
  if (branches.length === 0) {
    return null;
  }
  return branches[branches.length - 1];
}

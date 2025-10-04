# Slideshow Manager

A Next.js App Router project that manages one or more Slideshow appliances through a secure proxy. The project mirrors the feature set of the existing Flask-based Slideshow UI while adding fleet management tooling.

## Features

- Secure proxy layer that mirrors the native device API (state, config, playback, sources, media preview, logs, config import/export).
- HttpOnly session cookie management that stores the device session on the server side only.
- React Query powered dashboard with polling, cache invalidation and optimistic UI states.
- React Hook Form + Zod driven forms aligned with the API constraints for playback and source management.
- Multi-device registry with role-based access hooks and optional audit logging stubs.
- Modular UI components that can be themed and localized.

## Getting Started

1. **Install dependencies**

   ```bash
   pnpm install
   # or
   npm install
   ```

2. **Environment variables**

   Copy the example environment file and adapt it to your deployment.

   ```bash
   cp .env.example .env.local
   ```

   | Variable | Description |
   | --- | --- |
   | `SLIDESHOW_MANAGER_DEVICE_REGISTRY` | JSON string that defines allowed devices (see `.env.example`). |
   | `SLIDESHOW_MANAGER_SESSION_COOKIE` | Name of the HttpOnly cookie that stores the proxied device session. |
   | `SLIDESHOW_MANAGER_ALLOWED_HOSTS` | Comma separated whitelist of device hostnames/IPs for SSRF protection. |
   | `NEXTAUTH_SECRET` | Secret used to encrypt cookies (fallback for custom auth helpers). |

3. **Development server**

   ```bash
   pnpm run dev
   ```

4. **Testing**

   ```bash
   pnpm run lint
   pnpm run test
   ```

## Project Structure

- `app/` – Next.js App Router routes for UI and API proxy handlers.
- `components/` – Reusable UI and form components.
- `lib/` – Shared utilities for configuration, validation, proxy logic and auth helpers.
- `server/` – Server-only helpers (audit logging, scheduler stubs).
- `tests/` – Unit and integration tests (Jest + Testing Library stubs).

## Roadmap

- Implement advanced fleet dashboards and scheduling UIs.
- Connect audit log stubs to a persistent datastore (SQL/Prisma).
- Add end-to-end tests using Playwright.
- Harden import/export streaming with resumable uploads.

## License

MIT

## Deployment Automation

For automated installations and upgrades the repository ships with shell scripts located in `scripts/`:

- `scripts/install.sh` – installs the latest `version-x.x.x` branch (or a branch provided via `--branch`) into `/opt/Slideshow_Manager` by default, installs dependencies, runs a production build and configures a `systemd` unit (`slideshow-manager.service`) so the application starts automatically after boot. Run the installer with root privileges (`sudo scripts/install.sh`) so it can create `/opt/Slideshow_Manager` and place the service definition under `/etc/systemd/system`. Use `--service-user <name>` when the daemon should run as a non-root user. When no repository is specified explicitly the script falls back to `joni123467/Slideshow_Manager`. During execution the script ensures that Git, Curl, Tar, Node.js ≥ 18 and pnpm are present (via `apt`, `dnf`, `yum` or `pacman`) and writes the service unit with an expanded `PATH` that includes the local `node_modules/.bin` directory so CLI tools remain available to the daemon.
- `scripts/update.sh` – refreshes an existing installation to a selected version, triggers a rebuild and schedules a restart of the `systemd` unit once the update completed. If Git is not available the script falls back to downloading an archive via HTTPS.

Both scripts rely on the environment variable `SLIDESHOW_MANAGER_REPO` (format: `owner/repo`) when a Git remote cannot be inferred automatically. Optional authentication against the GitHub API can be configured with `SLIDESHOW_MANAGER_REPO_TOKEN`. If you maintain a fork and want to change the baked-in default, set `SLIDESHOW_MANAGER_DEFAULT_REPO` before running the scripts or pass `--repo <owner/repo>` explicitly. The update flow is also exposed in the dashboard UI (`/updates`) which lists available branches and allows administrators to trigger the shell updater directly from the browser. Updates initiated from the web interface return success immediately and restart the daemon a few seconds later so the HTTP response can complete before the service restarts.

### Downloading the installer via `wget`

To install on a fresh machine without cloning the repository, download the installer script directly and execute it with elevated privileges. The commands below fetch the script from the `main` branch of this repository; adjust the branch or repository if you are using a fork.

```bash
wget -O install.sh https://raw.githubusercontent.com/joni123467/Slideshow_Manager/main/scripts/install.sh
chmod +x install.sh
sudo ./install.sh
```

The installer automatically selects the newest `version-x.x.x` branch. Use `--branch version-1.2.3` to pin a specific release or `--repo <owner/repo>` to target a different repository.

### What gets installed automatically?

When invoked with administrative privileges the installer attempts to provision every runtime dependency that Slideshow Manager requires:

- `git`, `curl`, `tar` and certificate bundles used for fetching releases and archives.
- A modern Node.js runtime (currently Node 20 via NodeSource packages on Debian/Ubuntu/RHEL/Fedora derivatives, or the distribution packages on Arch-based systems).
- `pnpm` (via Corepack or npm) so production builds and the system service can call the bundled scripts.

If your distribution exposes none of the supported package managers (`apt`, `dnf`, `yum`, `pacman`) the script aborts with an explicit error message so you can install the prerequisites manually before re-running the installer.

After installation the service can be controlled via the usual `systemd` commands:

```bash
sudo systemctl status slideshow-manager.service
sudo systemctl restart slideshow-manager.service
sudo systemctl disable --now slideshow-manager.service
```

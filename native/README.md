# AzuraCast-LXC: AzuraCast natively on Debian 13

[Nederlands](README.nl.md)

This fork runs [AzuraCast](https://www.azuracast.com) directly on Debian 13 (trixie), for example in a
Proxmox LXC container, **without Docker**. The application itself is upstream AzuraCast; only the way it
is installed, started and updated is different.

## Requirements

- Debian 13 (trixie), amd64, a fresh system or container
- At least 2 vCPU and 4 GB RAM; disk space for your music library
- Proxmox LXC: enable **nesting** (Options → Features). Liquidsoap uses bubblewrap as a sandbox, which
  needs user namespaces.
- Ports: 80/443 (web), 2022 (SFTP), 8000–8499 (stations)

## Install

```bash
# Production channel (main)
curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/main/native/install.sh | sudo bash

# Test channel
curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/test/native/install.sh | sudo bash -s -- --channel test
```

Then open `http://<server>/` and create the first administrator. Running behind a reverse proxy such as
Zoraxy: set the IP source in *Administration → System Settings → Security & Privacy* and leave HTTPS to
the proxy.

## Managing it

| Command | What it does |
|---|---|
| `azuracast-ctl status` | Service and process status |
| `azuracast-ctl restart` | Restart everything |
| `azuracast-ctl logs [nginx\|php-fpm\|mariadb\|...]` | Follow logs |
| `azuracast-ctl version` | Installed release, channel, AzuraCast version |
| `azuracast-ctl check` | Is there a newer release? |
| `azuracast-ctl update` | Update (database backup first, automatic rollback on failure) |
| `azuracast-ctl channel main\|test` | Switch between production and test |
| `azuracast-ctl backup` / `restore <file>` | AzuraCast's own backup and restore |
| `azuracast-ctl cli <command>` | Any AzuraCast console command |

Updates can also be started from *Administration → Updates* in the web interface. The update check uses
this repository's GitHub releases, not AzuraCast's update server.

Settings live in `/etc/azuracast/azuracast.env` (run `azuracast-ctl restart` after a change).

## How it works

- Same directory layout as the Docker image: code in `/var/azuracast/www`, stations in
  `/var/azuracast/stations`, backups in `/var/azuracast/backups`. Backups move between Docker and native
  installs.
- One systemd service, `azuracast.service`, runs supervisord, exactly like the container: MariaDB, Valkey
  (Redis), nginx, PHP-FPM, Centrifugo, SFTPGo, the queue workers, cron (supercronic) and every station's
  Liquidsoap and Icecast. AzuraCast controls the stations through supervisord, so this is kept as is.
- The installer reuses the upstream scripts in `util/docker` (Liquidsoap, ffmpeg, nginx, Centrifugo,
  SFTPGo, ...), so version bumps upstream come along automatically. PHP 8.5 comes from packages.sury.org,
  MariaDB from Debian.
- Icecast-KH (AzuraCast build) and the built-in documentation are copied at build time from the same pinned
  images the upstream Dockerfile uses. Nothing runs in Docker on the server.
- The file `/var/azuracast/.native` switches the application to native mode (`Environment::isNative()`):
  paths and sockets as in Docker, the update check against GitHub releases, and the web updater through the
  `azuracast-updater` systemd path unit.
- Services that Docker kept on its private network (Valkey, the Centrifugo API) are bound to localhost.

## Branches and releases

- `main` = production. A push builds release `vX.Y.Z` from `native/VERSION` (bump it to publish again).
- `test` = test. Every push builds prerelease `vX.Y.Z-test.N`.
- Changes go through pull requests: first to `test`, then from `test` to `main`.

## Differences from Docker AzuraCast

- Not supported by the AzuraCast project; report problems in this repository.
- No `docker.sh`, no updater container, no `PUID`/`PGID` and no `INSTALL_PACKAGES_ON_STARTUP` (use apt).
- Composer plugin mode is not supported.
- amd64 only for now.

# AzuraCast-LXC: AzuraCast native op Debian 13

[English](README.md)

Deze fork draait [AzuraCast](https://www.azuracast.com) rechtstreeks op Debian 13 (trixie), bijvoorbeeld in
een Proxmox LXC-container, **zonder Docker**. De applicatie zelf is gewoon AzuraCast; alleen de manier van
installeren, starten en updaten is anders.

## Eisen

- Debian 13 (trixie), amd64, een schoon systeem of een nieuwe container
- Minimaal 2 vCPU en 4 GB RAM; schijfruimte voor je muziekbibliotheek
- Proxmox LXC: zet **nesting** aan (Opties → Features). Liquidsoap gebruikt bubblewrap als sandbox en dat
  heeft user namespaces nodig.
- Poorten: 80/443 (web), 2022 (SFTP), 8000–8499 (stations)

## Installeren

```bash
# Productiekanaal (main)
curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/main/native/install.sh | sudo bash

# Testkanaal
curl -fsSL https://raw.githubusercontent.com/rhisijmuiden/azuracast-lxc/test/native/install.sh | sudo bash -s -- --channel test
```

Open daarna `http://<server>/` en maak de eerste beheerder aan. Achter een reverse proxy zoals Zoraxy: stel
de IP-bron in bij *Beheer → Systeeminstellingen → Beveiliging en privacy* en laat HTTPS aan de proxy over.

## Beheren

| Commando | Wat het doet |
|---|---|
| `azuracast-ctl status` | Status van de service en processen |
| `azuracast-ctl restart` | Alles herstarten |
| `azuracast-ctl logs [nginx\|php-fpm\|mariadb\|...]` | Logs volgen |
| `azuracast-ctl version` | Geïnstalleerde release, kanaal, AzuraCast-versie |
| `azuracast-ctl check` | Is er een nieuwere release? |
| `azuracast-ctl update` | Updaten (eerst databaseback-up, bij een fout automatisch terug) |
| `azuracast-ctl channel main\|test` | Wisselen tussen productie en test |
| `azuracast-ctl backup` / `restore <bestand>` | De eigen back-up en restore van AzuraCast |
| `azuracast-ctl cli <commando>` | Elk AzuraCast-consolecommando |

Updaten kan ook via *Beheer → Updates* in de webinterface. De updatecheck kijkt naar de GitHub-releases van
deze repository, niet naar de updateserver van AzuraCast.

Instellingen staan in `/etc/azuracast/azuracast.env` (daarna `azuracast-ctl restart`).

## Hoe het werkt

- Dezelfde mappen als in het Docker-image: code in `/var/azuracast/www`, stations in
  `/var/azuracast/stations`, back-ups in `/var/azuracast/backups`. Back-ups zijn uitwisselbaar tussen een
  Docker- en een native installatie.
- Eén systemd-service, `azuracast.service`, draait supervisord, precies zoals in de container: MariaDB,
  Valkey (Redis), nginx, PHP-FPM, Centrifugo, SFTPGo, de queue-workers, cron (supercronic) en per station
  Liquidsoap en Icecast. AzuraCast bestuurt de stations via supervisord, daarom blijft dat zo.
- De installer gebruikt de upstream-scripts in `util/docker` (Liquidsoap, ffmpeg, nginx, Centrifugo, SFTPGo,
  ...), dus versie-updates van upstream komen vanzelf mee. PHP 8.5 komt van packages.sury.org, MariaDB uit
  Debian.
- Icecast-KH (AzuraCast-versie) en de ingebouwde documentatie worden bij het bouwen gekopieerd uit dezelfde
  vastgepinde images die de upstream-Dockerfile gebruikt. Op de server draait niets in Docker.
- Het bestand `/var/azuracast/.native` zet de applicatie in native-modus (`Environment::isNative()`): paden
  en sockets zoals in Docker, de updatecheck tegen de GitHub-releases en de web-updater via de systemd
  path-unit `azuracast-updater`.
- Diensten die Docker op zijn eigen privénetwerk hield (Valkey, de Centrifugo-API) luisteren alleen op
  localhost.

## Branches en releases

- `main` = productie. Een push bouwt release `vX.Y.Z` uit `native/VERSION` (verhoog die om opnieuw te
  publiceren).
- `test` = test. Elke push bouwt prerelease `vX.Y.Z-test.N`.
- Wijzigingen gaan via pull requests: eerst naar `test`, daarna van `test` naar `main`.

## Verschillen met Docker-AzuraCast

- Niet ondersteund door het AzuraCast-project; meld problemen in deze repository.
- Geen `docker.sh`, geen updater-container, geen `PUID`/`PGID` en geen `INSTALL_PACKAGES_ON_STARTUP`
  (gebruik apt).
- Composer-pluginmodus wordt niet ondersteund.
- Voorlopig alleen amd64.

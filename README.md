# Storager 2 · Proxmox-Installer

Oeffentlicher Bootstrap fuer den interaktiven Storager-2-LXC-Installer. Der
Storager-Quellcode und alle Zugangsdaten bleiben im privaten Repository.

## Start in der Proxmox-VE-Shell

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Calcoon/storager2-installer/main/install.sh)"
```

Der Bootstrap fragt nach dem absoluten Pfad einer lokalen, nichtleeren
GitHub-Token-Datei mit Modus `0600` oder `0400`. Das Token benoetigt nur
Lesezugriff auf `Calcoon/Storager`. Es wird weder in einer URL noch in
Prozessargumenten, Git-Remotes oder Logs gespeichert.

Danach wird der aktuelle `storager2`-Channel temporaer nach `/tmp` geladen und
der dort versionierte Installer gestartet. Dieser fragt unter anderem:

- neue CT-ID, Storage und Template-Storage;
- Netzwerkbruecke, DHCP oder statische IP;
- CPU, RAM, Disk und Swap;
- optional `cloudflared`, separaten S2-Host und Tunnel-Token-Datei;
- abschliessende Bestaetigung vor der ersten dauerhaften Aenderung.

Der temporaere Checkout und das Askpass-Skript werden beim Beenden entfernt.
Die vom Betreiber bereitgestellten Token-Dateien bleiben an ihrem urspruenglichen
Ort und werden nicht geloescht.

## Sicherheitsgrenzen

- Der Zielchannel ist fest `storager2`.
- Storager 1, dessen Container, Domain, Dienst, Daten und Backups sind gesperrt.
- Die eigentliche Installation kommt aus dem privaten Storager-Repository; in
  diesem oeffentlichen Repository liegt keine zweite Provisioninglogik.
- Ein echter Lauf bleibt bis zu einer bestaetigten Auswahl interaktiv.
- Cloudflare-DNS und die externe Erreichbarkeit werden nicht erfunden. Sie
  bleiben nach der technischen Einrichtung sichtbare Abnahmegates.

## Ohne Einzeiler pruefen

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Calcoon/storager2-installer/main/install.sh \
  -o /tmp/storager2-install.sh
less /tmp/storager2-install.sh
bash /tmp/storager2-install.sh
```

GitHub Packages ist fuer diesen Bootstrap nicht erforderlich. Falls Storager 2
spaeter als OCI-Image ausgeliefert wird, kann die GitHub Container Registry als
getrennter Distributionsweg bewertet werden.

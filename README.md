# Storager 2 · Proxmox-Installer

Oeffentlicher Bootstrap fuer den interaktiven Storager-2-LXC-Installer. Der
Storager-Quellcode und alle Zugangsdaten bleiben im privaten Repository.

## Start in der Proxmox-VE-Shell

```bash
STORAGER2_BOOTSTRAP_URL="https://raw.githubusercontent.com/Calcoon/storager2-installer/refs/heads/main/install.sh"
bash -c "$(curl -fsSL "$STORAGER2_BOOTSTRAP_URL")"
```

Der Bootstrap fragt standardmaessig im interaktiven Modus:

- GitHub-Token (direkt als Wert, **nicht** mit `--token`)
- optional Cloudflare-Token (enter = ueberspringen)
- CT-Parameter wie ID, Ressourcen, Zeit, DNS/Tunnel-Optionen

Das GitHub-PAT ist das alte Token nur als `github_pat_...` oder klassisch.
Es wird nicht als URL, CLI-Argument oder Log ausgegeben.

## Token-Eingabe und -Modus

Das Skript akzeptiert beide Wege:

1. Interaktiv:
   - GitHub: Token einfach eintippen/pasten, nur der Wert.
   - Cloudflare: Token einfach eintippen/pasten, nur der Wert.

2. Datei-basiert (nicht-interaktiv):
   - `STORAGER2_GIT_TOKEN_FILE`: absolute Datei mit GitHub-Token
   - `STORAGER2_CLOUDFLARE_TOKEN_FILE`: absolute Datei mit Cloudflare-Token

Beispiel:

```bash
printf '%s\n' 'github_pat_xxx...' > /root/.storager2-read-token
printf '%s\n' 'ey...cloudflare...' > /root/.storager2-cloudflare-token
chmod 0600 /root/.storager2-read-token /root/.storager2-cloudflare-token

STORAGER2_GIT_TOKEN_FILE=/root/.storager2-read-token \
STORAGER2_CLOUDFLARE_TOKEN_FILE=/root/.storager2-cloudflare-token \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Calcoon/storager2-installer/refs/heads/main/install.sh)"
```

## Ablauf

Der Bootstrap lädt den privaten `storager2`-Channel temporär nach `/tmp`, prüft
den Checkout, und startet danach den versiehenen S2-Installer im selben Lauf.
Der temporaere Checkout und das Askpass-Skript werden beim Beenden entfernt.
Die vom Betreiber bereitgestellten Token-Dateien bleiben am urspruenglichen Ort.

Danach fragt der Provisioner interaktiv nach:

- neue CT-ID, Storage und Template-Storage
- Netzwerkbruecke, DHCP oder statische IP
- CPU, RAM, Disk und Swap
- optional `cloudflared`, separaten S2-Host und Tunnel-Token-Datei
- abschliessende Bestaetigung vor der ersten dauerhaften Aenderung

## Cloudflare-URL und Tunnel-Token in der Praxis

- Im Installer gibst du den **öffentlichen Hostnamen** z. B. `storagerv2.frigen.de` ein.
- Der Cloudflare-Dienst wird im Container als Tunnel-Ziel auf `http://127.0.0.1:8000` konfiguriert.
- Beim Token-Dialog gibst du immer nur den **rohen Token-String** ein.
  `--token` wird nicht verwendet.

## Sicherheitsgrenzen

- Der Zielchannel ist fest `storager2`.
- Storager 1, dessen Container, Domain, Dienst, Daten und Backups sind gesperrt.
- Die eigentliche Installation kommt aus dem privaten Storager-Repository; in diesem
  oeffentlichen Repository liegt keine zweite Provisioninglogik.
- Ein echter Lauf bleibt bis zu einer bestaetigten Auswahl interaktiv.

## Ohne Einzeiler prüfen

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Calcoon/storager2-installer/refs/heads/main/install.sh \
  -o /tmp/storager2-install.sh
less /tmp/storager2-install.sh
bash /tmp/storager2-install.sh
```

Wenn du auch bei dieser URL plötzlich eine alte Version siehst, dann kannst du
für absolute Konsistenz temporär per Commit-Pin arbeiten:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Calcoon/storager2-installer/24e76fb31f2f4b0fb2f6fc9a6be8cb1f6cb3cbf1/install.sh
```

GitHub Packages ist fuer diesen Bootstrap nicht erforderlich. Falls Storager 2
spaeter als OCI-Image ausgeliefert wird, kann die GitHub Container Registry als
getrennter Distributionsweg bewertet werden.

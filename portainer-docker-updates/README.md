# Portainer Docker Image Updates für Zabbix

## Zweck und Architektur

Das Template überwacht lesend, ob für die Images vorhandener Docker-Container ein
neuer Digest unter demselben Image-Tag verfügbar ist. Ein External Check auf dem
Zabbix Server oder Proxy ruft das Bash-Skript ohne Parameter auf. Das Skript liest
lokale Konfiguration und API-Key, fragt mehrere Portainer-Environments ab und gibt
ein stabiles JSON-Dokument aus. Abhängige Items und Low-Level Discovery zerlegen
diese eine Antwort; dadurch gibt es nur einen geplanten External Check.

Das Projekt zieht keine Images, ersetzt keine Container und führt keine Updates aus.
Insbesondere ist ein angezeigtes PostgreSQL-Image-Update keine Freigabe für ein
automatisches Upgrade. Major-Upgrades wie PostgreSQL 15 auf 16 benötigen in der
Regel eine geplante Migration.

## Voraussetzungen und Kompatibilität

- Zabbix 7.0 oder neuer (Exportformat 7.0; vorgesehen für Zabbix 7.x einschließlich 7.4)
- Portainer Business Edition (BE) mit Docker-/Swarm-Environment und verfügbarer
  Container-Image-Status-API
- Bash 4+, `curl`, `jq`, `mktemp` und GNU-/POSIX-`date`
- HTTPS-Zugriff vom ausführenden Zabbix Server oder Proxy zu Portainer
- für die Offline-Tests zusätzlich `perl` mit `IO::Socket::INET`; `shellcheck` ist optional

Der Image-Status-Endpunkt wurde laut offiziellen Release Notes mit Portainer 2.18.1
eingeführt. Er ist jedoch nicht Bestandteil von Portainer CE 2.45.1: Dessen
veröffentlichter Container-Handler registriert nur die Routen `gpus` und `recreate`.
Portainer CE wird deshalb von diesem Template nicht unterstützt. Erforderlich ist
eine BE-Version, die `GET /api/docker/{environmentId}/containers/{containerId}/image_status`
tatsächlich bereitstellt. Die Implementierung wurde am 6. Oktober 2026 gegen die
offizielle Dokumentation und die Quellstände von CE 2.45.1 geprüft, aber nicht gegen
eine reale BE-Instanz jeder Version. Vor produktivem Einsatz ist ein API-Test mit
der konkret eingesetzten BE-Version erforderlich.

## Verwendete Portainer-API

Es werden ausschließlich diese GET-Aufrufe ausgeführt:

1. `GET /api/endpoints/{environmentId}/docker/containers/json?all=false` listet über
   Portainers Docker-API-Proxy laufende Container. Mit `INCLUDE_STOPPED=true` wird
   `all=true` verwendet. Erwartet wird das Docker-Array mit mindestens `Id`, `Names`,
   `Image` und `State`.
2. `GET /api/docker/{environmentId}/containers/{containerId}/image_status` liefert
   ein Objekt mit dem String-Feld `Status`.

Authentifiziert wird mit `X-API-Key`. Offizielle Referenzen:

- [Portainer API usage examples](https://docs.portainer.io/api/docs) und
  [Docker-Proxy-Beispiel](https://docs.portainer.io/sts/api/examples)
- [Portainer Release Notes](https://docs.portainer.io/release-notes)
- [Funktionsweise des Image-Indikators](https://docs.portainer.io/faqs/troubleshooting/stacks-deployments-and-updates/how-does-the-image-update-notification-icon-work)
- [Statusdefinition und Cache im Portainer-Quellcode](https://github.com/portainer/portainer/blob/develop/api/docker/images/status.go)
- [CE-2.45.1-Container-Routen ohne Image-Status-Endpunkt](https://github.com/portainer/portainer/blob/2.45.1/api/http/handler/docker/containers/handler.go)

Mapping der Portainer-Antwort:

| Portainer / Situation | Interner Status | Update |
|---|---|---:|
| `Status == "updated"` | `updated` | nein |
| `Status == "outdated"` | `outdated` | ja |
| `Status == "error"` | `error` | nein |
| `processing`, `skipped`, `preparing` oder anderer gültiger String | `unknown` | nein |
| HTTP-, Transport-, TLS- oder JSON-Fehler | `error` | nein |
| durch lokalen Filter übersprungen | `excluded` | nein |

Es werden keine erfundenen numerischen oder booleschen Portainer-Statuswerte
akzeptiert. Unbekannte zukünftige Strings bleiben sichtbar als `unknown`.

Portainer BE vergleicht lokale Image-Digests mit dem entfernten Digest des gleichen
Image-Tags. Die Antwort kann gecacht sein. Der am 6. Oktober 2026 geprüfte
`develop`-Quellcode definiert 24 Stunden für den Resource-Status, 5 Minuten für
Fehlerstatus und 5 Sekunden für Remote-Digests; veröffentlichte Versionen können
abweichen. Dieses Projekt leert den Cache nicht, weil der dafür vorgesehene
API-Aufruf schreibend ist. Ein gerade veröffentlichtes Image kann daher verzögert
erscheinen.

Private Registries funktionieren nur, wenn Portainer die passenden Registry-
Zugangsdaten dem Environment/Image zuordnen kann. Fehlende Berechtigung, ein nicht
auflösbarer Digest, manifest-list-/Architektur-Besonderheiten oder ein nur als Hash
bekanntes Image können zu `unknown` oder `error` führen. Docker Hub und andere
Registries können HEAD-/Manifest-Anfragen begrenzen; HTTP 429 wird als Fehler
ausgegeben. Ein längeres Zabbix-Intervall reduziert Registry-Last und Rate-Limits.

## Installation auf Zabbix Server oder Proxy

Der Check muss auf dem Prozess installiert werden, der das Template ausführt. Bei
einem überwachten Host mit zugewiesenem Proxy ist dies normalerweise der Proxy.
Den tatsächlichen Pfad zuerst über `ExternalScripts` in `zabbix_server.conf` oder
`zabbix_proxy.conf` prüfen; `/usr/lib/zabbix/externalscripts` ist nur der hier
verwendete Standard.

```bash
sudo install -o root -g zabbix -m 0750 \
  portainer-docker-updates/portainer_docker_updates.sh \
  /usr/lib/zabbix/externalscripts/portainer_docker_updates.sh
sudo install -o root -g zabbix -m 0640 \
  portainer-docker-updates/portainer-docker-updates.conf.example \
  /etc/zabbix/portainer-docker-updates.conf
sudo install -o root -g zabbix -m 0640 /dev/null /etc/zabbix/portainer-api-key
sudoedit /etc/zabbix/portainer-docker-updates.conf
sudoedit /etc/zabbix/portainer-api-key
```

Die Key-Datei enthält nur den API-Key in der ersten Zeile. Das Skript übergibt ihn
über eine temporäre Headerdatei an `curl`; er erscheint weder in Prozessargumenten
noch im JSON oder in Diagnosen. Temporäre Dateien haben Modus 0600 innerhalb eines
0700-Verzeichnisses und werden per `trap` entfernt.

### API-Key und minimale Berechtigungen

In Portainer unter **My account → Access tokens** einen Token für einen dedizierten
Monitoring-Benutzer erstellen. Ein Access Token erbt die Rechte dieses Benutzers;
Portainer bietet am Token selbst keine unabhängigen Scopes. Der Benutzer braucht
nur Leserechte auf die konfigurierten Docker-Environments sowie Zugriff auf
Containerliste und Image-Status. Keine Administratorrechte vergeben, sofern die
verwendete BE-Version und deren RBAC dies nicht erfordern. Zugriff mit diesem
Benutzer vorab in der konkreten Installation prüfen.

### Konfiguration

```bash
PORTAINER_URL="https://portainer.example.local"
PORTAINER_API_KEY_FILE="/etc/zabbix/portainer-api-key"
PORTAINER_ENVIRONMENTS="1:docker01,2:docker02"
VERIFY_TLS="true"
CA_FILE=""
CONNECT_TIMEOUT="10"
REQUEST_TIMEOUT="30"
INCLUDE_STOPPED="false"
CONTAINER_INCLUDE_REGEX=""
CONTAINER_EXCLUDE_REGEX=""
IMAGE_EXCLUDE_REGEX=""
```

Environment-Einträge haben das Format `numerische-id:anzeigename` und werden durch
Kommas getrennt. Weitere Hosts werden einfach angehängt, zum Beispiel
`1:docker01,2:docker02,7:edge-docker`. Reguläre Ausdrücke sind Bash-ERE. Ein
Include-Filter schließt nicht passende Container aus; Exclude-Filter haben Vorrang.
Ausgeschlossene Container bleiben im JSON mit Status `excluded` nachvollziehbar.

Die Konfiguration wird mit Bash `source` geladen und ist damit vertrauenswürdiger
Bash-Code, nicht nur ein Datenformat. Sie muss `root:zabbix` gehören, Modus 0640
haben und darf ausschließlich durch Administratoren veränderbar sein. Werte werden
danach nur als quotierte Daten verwendet; das Skript nutzt kein `eval`.

Für eine interne CA:

```bash
VERIFY_TLS="true"
CA_FILE="/etc/zabbix/portainer-ca.pem"
```

`VERIFY_TLS=false` ist nur für einen eng begrenzten Test vorgesehen. Standardmäßig
wird das Zertifikat einschließlich Hostname geprüft.

## Template importieren und verknüpfen

1. In Zabbix **Data collection → Templates → Import** öffnen.
2. `template_portainer_docker_updates.yaml` importieren.
3. Das Template **Portainer Docker Image Updates** mit genau einem technischen Host
   verknüpfen, der den Zabbix Server beziehungsweise richtigen Proxy repräsentiert.
4. Nach der ersten Ausführung Master-Item, abhängige Items und Discovery prüfen.

Das Template enthält keine URL, Environment-ID und keine Zugangsdaten. Item-Keys
verwenden Environment- und Container-IDs; Namen und Images mit Sonderzeichen stehen
nur in Werten, LLD-Makros und Anzeigenamen.

## Manuelle und negative Tests

```bash
sudo -u zabbix /usr/lib/zabbix/externalscripts/portainer_docker_updates.sh | jq .
sudo -u zabbix /usr/lib/zabbix/externalscripts/portainer_docker_updates.sh | jq empty
```

Für einen falschen API-Key temporär eine separate Test-Key-Datei und Testkonfiguration
verwenden, nicht den produktiven Token überschreiben. Erwartet werden Exit-Code 2,
`status: "error"` (bei nur einem Environment) und ein 401-/403-Hinweis ohne Secret.
Für einen Erreichbarkeitstest kann in einer separaten Testkonfiguration etwa
`PORTAINER_URL="https://127.0.0.1:1"` gesetzt werden. Erwartet wird valides Fehler-JSON.

Offline-Tests aus dem Repository:

```bash
cd portainer-docker-updates
bash tests/test.sh
```

## Status, Exit-Codes und Fehlerbehebung

- `status=ok`, Exit 0: alle Environments ohne technische Fehler geprüft.
- `status=warning`, Exit 1: Teilerfolg; mindestens ein Container oder Environment
  ist technisch fehlgeschlagen, andere Ergebnisse sind auswertbar.
- `status=error`, Exit 2: Konfigurationsfehler oder alle Environments fehlgeschlagen.

Diagnosen gehen nur nach stderr; stdout enthält bei normalen Checks genau ein JSON-
Dokument. `--help` ist die einzige bewusst menschenlesbare stdout-Ausgabe.

Bei Fehlern zuerst als Benutzer `zabbix` testen, Dateirechte und `ExternalScripts`
prüfen, danach DNS, Firewall, Zertifikatskette, Portainer-Benutzerrechte und die
Registry-Zuordnung kontrollieren. 401/403 deutet auf Token oder RBAC, 429 auf ein
Registry-/API-Rate-Limit, `unknown` auf einen von Portainer nicht erkannten Status.
Gestoppte Container fehlen standardmäßig absichtlich.

Ein 404 bereits bei der Containerliste bedeutet, dass die konfigurierte Environment-ID
nicht existiert oder für den Token nicht sichtbar ist. Die IDs müssen aus Portainer
übernommen werden und sind nicht zwingend fortlaufend. Liefert dagegen die
Containerliste Daten, aber jeder Image-Status-Aufruf 404, fehlt die Image-Status-API;
dies ist bei Portainer CE 2.45.1 das erwartete Verhalten.

## API-Key rotieren und Secret-Prüfung

Neuen Token anlegen, die Key-Datei atomar beziehungsweise während eines kurzen
Wartungsfensters ersetzen, den Check als `zabbix` testen und erst danach den alten
Token in Portainer widerrufen. Anschließend prüfen:

```bash
git status --short
git diff --check
git grep -nE 'ptr_[A-Za-z0-9_-]+|X-API-Key:[[:space:]]*[^$]' -- . \
  ':(exclude)portainer-docker-updates/README.md'
```

Vor jedem Commit zusätzlich `git diff --cached` kontrollieren. Niemals die echte
Konfiguration, Key-Datei, CA-Private-Keys oder rohe Portainer-Antworten einchecken.

## Bekannte Einschränkungen

- Portainer CE einschließlich CE 2.45.1 stellt den benötigten Endpunkt nicht bereit.
  Das Skript meldet das Environment bei durchgängigen Image-Status-404-Antworten als
  `error`; es gibt bewusst keinen erfundenen oder unvollständigen Registry-Fallback.
- Die Erkennung bewertet denselben Tag per Digest; sie sucht keine höheren Tags und
  entscheidet nicht, ob ein Upgrade fachlich sicher ist.
- Registry-Erreichbarkeit und -Authentifizierung erfolgen durch Portainer.
- Cache-Verhalten und RBAC können sich zwischen Portainer-Versionen unterscheiden.
- Ein echter Importtest benötigt eine Zabbix-7.0+-Instanz; die Offline-Tests können
  nur YAML-Struktur, Referenzen und Preprocessing-Plausibilität prüfen.

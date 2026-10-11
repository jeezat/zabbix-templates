Du bist ein erfahrener Zabbix-, Portainer- und Bash-Administrator.

Arbeite direkt in meinem bestehenden Git-Repository `zabbix-templates` und erstelle eine produktionsnahe Zabbix-Überwachung für verfügbare Docker-Image-Updates über die Portainer-API.

ZIELSTRUKTUR

zabbix-templates/
├── README.md
└── portainer-docker-updates/
    ├── README.md
    ├── template_portainer_docker_updates.yaml
    ├── portainer_docker_updates.sh
    ├── portainer-docker-updates.conf.example
    └── tests/
        └── test.sh

Die Root-README ist die zentrale Übersicht für alle jetzigen und zukünftigen Templates. Sie enthält eine Tabelle der verfügbaren Templates und verweist für Details auf die jeweilige Unter-README. Die vollständige Installationsanleitung gehört in `portainer-docker-updates/README.md`.

ZIELUMGEBUNG

- Zabbix 7.4 oder eine möglichst breit kompatible Zabbix-7.x-Version
- Portainer CE oder BE
- mehrere Portainer-Environments beziehungsweise Docker-Hosts
- Ausführung als Zabbix External Check auf dem Zabbix Server oder Proxy
- Bash 4 oder neuer
- curl und jq
- keine Python-Abhängigkeiten
- Portainer-Zugriff per HTTPS und API-Key
- ausschließlich lesender Zugriff; keine Container verändern oder aktualisieren

PORTAINER-API

Prüfe die verwendeten Endpunkte und deren Antwortstruktur anhand der offiziellen Portainer-Dokumentation beziehungsweise der zur Portainer-Version gehörenden Swagger/OpenAPI-Dokumentation.

Voraussichtlich benötigte Endpunkte sind:

- Auflisten der Container eines Environments über den Docker-API-Proxy
- Prüfen eines Containers über:
  GET /api/docker/{environmentId}/containers/{containerId}/image_status

Verwende keine erfundenen Endpunkte oder Statuswerte. Prüfe insbesondere, ob die Antwort des Image-Status-Endpunkts Strings, Zahlen oder boolesche Werte liefert, und mappe die tatsächlichen Werte nachvollziehbar auf die internen Statuswerte.

Dokumentiere:

- verwendete Endpunkte,
- erwartete Antwortstruktur,
- unterstützte oder geprüfte Portainer-Versionen,
- bekannte Einschränkungen,
- Caching des Image-Status,
- Verhalten bei privaten Registries und Rate-Limits.

Falls die Funktion mit der eingesetzten Portainer-Version nicht zuverlässig per offizieller API verfügbar ist, erfinde keine Ersatzfunktion. Dokumentiere die Einschränkung und implementiere nur dann einen Registry-Digest-Vergleich, wenn dieser mit Bash, curl und jq sicher und wartbar möglich ist.

BASH-SKRIPT

Erstelle `portainer_docker_updates.sh`.

Das Skript muss:

- mit `set -Eeuo pipefail` arbeiten,
- mehrere Portainer-Environments prüfen,
- standardmäßig nur laufende Container berücksichtigen,
- optional auch gestoppte Container prüfen,
- verfügbare Updates je Environment und Container erkennen,
- ausschließlich lesende API-Aufrufe ausführen,
- seine Konfiguration aus einer geschützten Datei lesen,
- den API-Key aus einer separaten geschützten Datei lesen,
- keine Secrets in stdout, stderr, Logs oder Prozessargumenten ausgeben,
- TLS-Zertifikate standardmäßig prüfen,
- optional eine eigene CA-Datei unterstützen,
- Verbindungs-, Timeout-, TLS-, HTTP-, Authentifizierungs- und JSON-Fehler erkennen,
- HTTP-Verbindungs- und Gesamt-Timeouts verwenden,
- Include- und Exclude-Regex für Container und Images unterstützen,
- JSON ausschließlich mit jq verarbeiten,
- temporäre Dateien sicher mit `mktemp` und `trap` behandeln,
- Diagnosemeldungen nur nach stderr schreiben,
- ausschließlich valides JSON nach stdout schreiben,
- einen verständlichen `--help`-Text besitzen,
- sinnvolle Exit-Codes verwenden,
- auch bei Teilfehlern nach Möglichkeit eine auswertbare JSON-Antwort liefern.

Beispielkonfiguration:

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

Behandle Konfigurationswerte als Daten. Vermeide `eval` und andere unsichere Auswertungen. Falls die Konfiguration mit `source` geladen wird, dokumentiere, dass sie vertrauenswürdig sein und durch restriktive Dateirechte geschützt werden muss.

JSON-AUSGABE

Erzeuge eine stabile, für Zabbix geeignete Struktur nach diesem Muster:

{
  "status": "ok",
  "checked_at": "ISO-8601-Zeitstempel in UTC",
  "total_updates": 1,
  "total_errors": 0,
  "environments": [
    {
      "id": "1",
      "name": "docker01",
      "status": "ok",
      "updates": 1,
      "errors": 0,
      "containers": [
        {
          "id": "container-id",
          "name": "nginx",
          "image": "nginx:stable",
          "status": "outdated",
          "update_available": true,
          "error": null
        }
      ]
    }
  ]
}

Zulässige interne Statuswerte:

- updated
- outdated
- unknown
- error
- excluded

Dokumentiere die Bedeutung und das Mapping der tatsächlichen Portainer-Antworten auf diese Werte.

Unterscheide mindestens:

- vollständiger Erfolg: status = ok
- Teilerfolg: status = warning
- vollständiger Fehler: status = error

Gib niemals den API-Key, Authentifizierungsheader oder sensible Antwortdaten aus.

ZABBIX-TEMPLATE

Erstelle `template_portainer_docker_updates.yaml` als direkt importierbares Zabbix-7.0-kompatibles YAML-Template.

Das Template soll enthalten:

- eine passende Template-Gruppe,
- ein External-Check-Master-Item mit der vollständigen JSON-Ausgabe,
- abhängige Items mit JSONPath- oder JavaScript-Preprocessing,
- Low-Level Discovery für Environments,
- Low-Level Discovery für Container,
- Item-Prototypen je Environment und Container,
- Trigger beziehungsweise Trigger-Prototypen,
- Value Maps für numerische Statuswerte, falls erforderlich,
- sinnvolle Tags.

Das External-Check-Item soll das Skript ohne API-Key oder andere Secrets als Argument aufrufen, beispielsweise:

portainer_docker_updates.sh

Das Skript liest seine feste, geschützte Konfigurationsdatei selbst ein.

Discovery-Makros:

{#ENVIRONMENT_ID}
{#ENVIRONMENT_NAME}
{#CONTAINER_ID}
{#CONTAINER_NAME}
{#IMAGE}

Verwende für Item-Keys möglichst stabile IDs statt Container-Namen. Container-Namen und Images können Sonderzeichen enthalten und dürfen die Item-Keys nicht ungültig machen.

Benötigte Items:

- vollständige JSON-Antwort als Master-Item,
- Gesamtstatus,
- Zeitpunkt der letzten Prüfung,
- Gesamtanzahl verfügbarer Updates,
- Gesamtanzahl Fehler,
- Updates je Environment,
- Fehler je Environment,
- Status je Environment,
- Update-Status je Container,
- Update verfügbar je Container,
- Containername,
- Image-Name.

Benötigte Trigger:

- mindestens ein Image-Update verfügbar: Warning,
- Portainer-API oder Skript fehlerhaft: Average,
- Environment konnte nicht geprüft werden: Average,
- Containerstatus über mehrere Prüfungen unbekannt: Warning,
- Master-Item liefert für einen sinnvollen Zeitraum keine Daten: Average.

Verwende Tags wie:

component: docker
component: portainer
scope: update
scope: availability

Ein verfügbares Update ist kein Dienstausfall. Verwende deshalb dafür höchstens den Schweregrad Warning.

Das Template darf keine Portainer-URL, Environment-ID, Zugangsdaten oder API-Keys enthalten. Diese Werte bleiben in der lokalen Konfigurationsdatei außerhalb von Git.

INSTALLATION UND SICHERHEIT

Verwende und dokumentiere folgende Installationspfade:

/usr/lib/zabbix/externalscripts/portainer_docker_updates.sh
/etc/zabbix/portainer-docker-updates.conf
/etc/zabbix/portainer-api-key

Beachte, dass der tatsächliche ExternalScripts-Pfad aus der Konfiguration des Zabbix Servers oder Proxys ermittelt werden muss und abweichen kann.

Empfohlene Rechte:

- Skript: root:zabbix, Modus 0750
- Konfiguration: root:zabbix, Modus 0640
- API-Key-Datei: root:zabbix, Modus 0640

Dokumentiere den Test als Zabbix-Benutzer, zum Beispiel:

sudo -u zabbix /usr/lib/zabbix/externalscripts/portainer_docker_updates.sh | jq .

README-DATEIEN

Erstelle oder aktualisiere `zabbix-templates/README.md` mit:

- kurzer Beschreibung des Repositorys,
- Tabelle aller enthaltenen Templates,
- Link auf `portainer-docker-updates/README.md`,
- allgemeiner Repository-Struktur,
- kurzer Anleitung zum Hinzufügen weiterer Templates.

Erstelle `portainer-docker-updates/README.md` mit:

- Zweck und Architektur,
- Voraussetzungen,
- unterstützten Zabbix- und Portainer-Versionen,
- verwendeten API-Endpunkten,
- Installation auf Zabbix Server und Proxy,
- Erstellen und sichere Ablage des API-Keys,
- minimal erforderlichen Portainer-Berechtigungen,
- Konfiguration der Environments,
- Dateirechten,
- Import und Verknüpfung des Templates,
- manuellem Test als Benutzer zabbix,
- Test mit falschem API-Key,
- Test mit nicht erreichbarem Portainer,
- TLS mit eigener CA,
- privaten Registries und Docker-Hub-Rate-Limits,
- Erweiterung um weitere Environments,
- Fehlerbehebung,
- Rotation des API-Keys,
- Prüfung, dass Secrets nicht in Git enthalten sind.

Weise darauf hin, dass ein angezeigtes PostgreSQL-Image-Update keine Freigabe für ein automatisches Upgrade ist. Major-Upgrades wie PostgreSQL 15 auf 16 benötigen in der Regel eine geplante Migration. Dieses Projekt führt keine Updates aus.

TESTS

Erstelle `tests/test.sh`.

Die Tests dürfen keine echte Portainer-Instanz und keine echten Zugangsdaten benötigen. Verwende lokale Mock-Antworten oder einen kleinen lokalen Mock-HTTP-Server mit vorhandenen Standardwerkzeugen.

Prüfe mindestens:

- Shell-Syntax mit `bash -n`,
- optionale Prüfung mit ShellCheck, falls installiert,
- jede Skriptausgabe mit `jq empty`,
- fehlende Konfiguration,
- fehlende API-Key-Datei,
- ungültige Authentifizierung,
- nicht erreichbares Portainer,
- HTTP-Fehler,
- ungültiges JSON,
- mehrere Environments,
- leere Containerliste,
- Sonderzeichen in Container-Namen und Images,
- Include- und Exclude-Filter,
- Status updated,
- Status outdated,
- unbekannter Portainer-Status,
- Teilausfall eines Environments.

Tests dürfen keine produktiven Dateien unter `/etc` oder `/usr/lib` verändern.

VALIDIERUNG

Prüfe vor Abschluss:

- `bash -n` für alle Shell-Skripte,
- JSON-Ausgaben mit `jq empty`,
- sichere Quotierung aller Variablen,
- Behandlung leerer und fehlender Werte,
- Bereinigung temporärer Dateien,
- keine Secrets in Ausgaben,
- plausible Zabbix-Item-Keys,
- korrekte Master- und Dependent-Item-Beziehungen,
- plausible JSONPath-Ausdrücke,
- korrekte LLD-Makros,
- plausible Trigger-Ausdrücke,
- Zabbix-7.0-YAML-Struktur.

Behaupte keine erfolgreiche Prüfung oder Importierbarkeit, wenn das notwendige Prüfwerkzeug oder eine Zabbix-7.0-Testinstanz nicht verfügbar ist. Weise in diesem Fall klar darauf hin und beschreibe, wie die Prüfung durchgeführt werden kann.

AUSGABE UND ARBEITSWEISE

Arbeite direkt im vorhandenen Repository und erstelle beziehungsweise aktualisiere die Dateien vollständig.

Liefere anschließend nur:

1. eine kurze Architekturübersicht,
2. die erstellte oder geänderte Verzeichnisstruktur,
3. eine Zusammenfassung der Änderungen,
4. Installations- und Testbefehle,
5. durchgeführte Prüfungen,
6. verbleibende Annahmen und Einschränkungen.

Gib nicht den vollständigen Inhalt jeder Datei zusätzlich im Chat aus, wenn du die Dateien bereits direkt im Repository erstellt hast.

Verwende keine echten API-Keys, internen URLs oder produktiven Hostnamen. Überschreibe keine bereits vorhandenen, nicht zu diesem Projekt gehörenden Dateien. Prüfe eine vorhandene Root-README und erweitere sie, statt bestehende Inhalte unnötig zu löschen.
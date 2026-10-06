# Zabbix Templates

Dieses Repository enthält produktionsnahe, dokumentierte Zabbix-Templates und die
dazugehörigen Hilfsprogramme. Zugangsdaten und standortspezifische Konfigurationen
gehören nicht in dieses Repository.

## Verfügbare Templates

| Template | Zweck | Zielversion |
|---|---|---|
| [Portainer Docker Updates](portainer-docker-updates/README.md) | Verfügbare Docker-Image-Updates über die Portainer-API erkennen | Zabbix 7.x, Portainer BE mit Image-Status-API |

## Struktur

Jedes Template liegt in einem eigenen Unterverzeichnis. Dort befinden sich das
importierbare Zabbix-YAML, benötigte Skripte, eine Beispielkonfiguration, Tests und
die vollständige Installations- und Betriebsdokumentation. Diese Root-README bleibt
die zentrale Übersicht.

## Weiteres Template hinzufügen

1. Ein eindeutig benanntes Unterverzeichnis mit eigener `README.md` anlegen.
2. Exportdatei, Skripte, sichere Beispielkonfiguration und Offline-Tests gemeinsam ablegen.
3. Keine Secrets, internen URLs oder produktiven Hostnamen einchecken.
4. Das neue Template in der Tabelle oben ergänzen und seine unterstützten Versionen dokumentieren.

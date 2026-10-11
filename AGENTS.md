# AGENTS.md

## Zweck

Dieses Repository enthält mehrere Zabbix-Templates mit zugehörigen Skripten, Konfigurationen, Tests und Dokumentationen.

Diese Datei enthält nur allgemeine Regeln für das gesamte Repository. Projektspezifische Anforderungen gehören in eine eigene Markdown-Datei im jeweiligen Template-Unterordner.

## Repository-Struktur

Die grundlegende Struktur lautet:

zabbix-templates/
├── AGENTS.md
├── README.md
└── <template-name>/
    ├── <template-name>.md
    ├── README.md
    ├── template_<template-name>.yaml
    ├── scripts/
    ├── config/
    ├── tests/
    └── examples/

Nicht benötigte Dateien oder Verzeichnisse müssen nicht erstellt werden.

Template-Unterordner sollen:

- einen eindeutigen Namen in Kleinbuchstaben verwenden,
- Leerzeichen vermeiden,
- möglichst Bindestriche verwenden,
- fachlich voneinander getrennt bleiben.

## Projektspezifische Anforderungen

Vor Änderungen:

1. Prüfe den aktuellen Repository-Stand.
2. Lies die Root-README.
3. Suche im betreffenden Template-Unterordner nach einer Projektspezifikation.
4. Bevorzugte Dateinamen sind:
   - <template-name>.md
   - TASK.md
   - SPECIFICATION.md
5. Lies die passende Datei vollständig.
6. Befolge diese Datei zusätzlich zu den allgemeinen Regeln aus AGENTS.md.

Projektspezifische Anforderungen haben Vorrang vor allgemeinen Empfehlungen dieser Datei.

Wenn keine Projektspezifikation vorhanden ist und das Ziel nicht eindeutig aus dem Auftrag hervorgeht, frage nach.

## Root-README

Die Datei README.md im Repository-Stamm ist die zentrale Übersicht aller Templates.

Sie soll:

- das Repository kurz beschreiben,
- alle vorhandenen Templates auflisten,
- auf die jeweiligen Unterordner und Dokumentationen verweisen,
- um zukünftige Templates erweitert werden können.

Projektspezifische Installationsanleitungen gehören in die README des jeweiligen Template-Unterordners und sollen nicht unnötig in der Root-README dupliziert werden.

Wenn ein neues Template erstellt wird, aktualisiere die Root-README mit einem passenden Eintrag.

## Template-Dokumentation

Jedes umfangreichere Template soll eine eigene README.md besitzen.

Diese soll mindestens beschreiben:

- Zweck und Funktionsweise,
- Voraussetzungen,
- unterstützte Versionen,
- enthaltene Dateien,
- Installation und Konfiguration,
- Secret-Verwaltung,
- Import in Zabbix,
- Tests,
- Fehlerbehebung,
- bekannte Einschränkungen.

Die Dokumentation muss der tatsächlichen Implementierung entsprechen. Nicht getestete Funktionen oder Endpunkte dürfen nicht als sicher funktionsfähig dargestellt werden.

## Dateien und Änderungen

Arbeite grundsätzlich nur im betroffenen Template-Unterordner und an notwendigen gemeinsamen Dateien.

Beachte:

- Bestehende Dateien zuerst lesen.
- Bestehende Inhalte nicht unnötig löschen.
- Fachfremde Dateien nicht ändern.
- Vorhandene Namenskonventionen beibehalten.
- Keine echten Zugangsdaten, API-Keys, Tokens oder Passwörter speichern.
- Keine produktiven Secrets oder vertraulichen URLs in Beispieldateien verwenden.
- Beispielwerte eindeutig als Platzhalter kennzeichnen.
- Bereits vorhandene Templates nur ändern, wenn der Auftrag dies verlangt.

## Zabbix-Templates

Verwende ein offizielles, zur Zielversion passendes Zabbix-Exportformat.

Achte insbesondere auf:

- gültige YAML- oder XML-Struktur,
- korrekte Item-Typen,
- Master- und Dependent-Items,
- Discovery-Regeln,
- Item-Prototypen,
- Trigger-Ausdrücke,
- JSONPath- und JavaScript-Preprocessing,
- User Macros,
- Tags,
- fehlende Secrets.

Wenn keine Zabbix-Testinstanz verfügbar ist, darf keine erfolgreiche Importierbarkeit behauptet werden. Dokumentiere stattdessen, was manuell in Zabbix geprüft werden muss.

## Skripte

Skripte müssen den projektspezifischen Anforderungen entsprechen.

Allgemein gilt:

- Eingaben validieren.
- Variablen sicher quotieren.
- Fehler sauber behandeln.
- Keine Secrets ausgeben.
- Keine Zugangsdaten unnötig als Prozessargumente verwenden.
- Sinnvolle Exit-Codes verwenden.
- Verständliche Hilfe und Fehlermeldungen bereitstellen.
- Temporäre Dateien sicher behandeln.
- Keine destruktiven Aktionen ohne ausdrücklichen Auftrag ausführen.

Bei Bash soll nach Möglichkeit verwendet werden:

set -Eeuo pipefail

JSON darf nicht unsicher mit grep, sed oder regulären Ausdrücken verarbeitet werden. Verwende dafür ein geeignetes Werkzeug wie jq.

## Konfiguration und Secrets

Secrets gehören niemals ins Git-Repository.

Dazu zählen insbesondere:

- API-Keys,
- Passwörter,
- Tokens,
- private Schlüssel,
- produktive Zugangsdaten.

Verwende stattdessen projektspezifisch geeignete Methoden, zum Beispiel:

- geschützte Konfigurationsdateien,
- Umgebungsvariablen,
- Ansible Vault,
- Secret Stores,
- sichere Zabbix-Makros,
- restriktive Betriebssystemberechtigungen.

Beispielkonfigurationen dürfen ausschließlich Platzhalter enthalten.

## Tests und Validierung

Der notwendige Testumfang richtet sich nach dem jeweiligen Template.

Je nach Projekt sollen mindestens sinnvolle Prüfungen durchgeführt werden, zum Beispiel:

- Syntaxprüfung,
- Prüfung der Hilfeausgabe,
- Validierung von JSON-Ausgaben,
- Prüfung von Beispielkonfigurationen,
- Prüfung des Zabbix-Templateformats,
- manueller Import in Zabbix,
- Ausführung auf Zabbix Server oder Proxy,
- Prüfung von Berechtigungen, Netzwerk und TLS,
- Prüfung von Discovery, Items und Triggern.

Nicht ausgeführte Tests müssen klar benannt werden. Keine erfolgreichen Tests vortäuschen.

Tests dürfen keine produktiven Systeme verändern.

## Git

Keine Git-Commits oder Git-Pushes ausführen, außer dies wird ausdrücklich verlangt.

Vor Änderungen:

git status

Nach Änderungen:

git status
git diff --stat
git diff

Prüfe, dass nur erwartete Dateien geändert wurden.

## Arbeitsweise

Arbeite in dieser Reihenfolge:

1. Repository-Stand prüfen.
2. Root-README und relevante Dateien lesen.
3. Projektspezifikation suchen und lesen.
4. Anforderungen mit der vorhandenen Implementierung vergleichen.
5. Kurzen Plan erstellen.
6. Nur notwendige Dateien ändern.
7. Verfügbare Prüfungen ausführen.
8. Änderungen und Testergebnisse kontrollieren.
9. Annahmen und Einschränkungen dokumentieren.

Bei unklaren oder widersprüchlichen Anforderungen:

- keine wichtigen Annahmen verschweigen,
- vorhandene Dokumentation prüfen,
- bei sicherheitskritischen oder destruktiven Aktionen nachfragen,
- sonst die getroffene Annahme dokumentieren.

## Abschlussbericht

Nach Abschluss soll die Antwort kurz enthalten:

1. Erstellte oder geänderte Dateien.
2. Wesentliche Änderungen.
3. Ausgeführte Tests und Prüfungen.
4. Nicht mögliche Prüfungen.
5. Verbleibende Annahmen und Einschränkungen.

Gib nicht automatisch den vollständigen Inhalt aller Dateien im Chat aus, wenn sie direkt im Repository erstellt oder geändert wurden.
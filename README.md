# AIKI Referat — installasjon

Møtenotattaker som tar opp, transkriberer og skriver referat **lokalt på din
egen Mac**. Lyd og transkript forlater aldri maskinen.

Krever en Mac med Apple Silicon (M1 eller nyere) og macOS 13 eller nyere.

---

## Installer

Åpne **Terminal** (finn den med Cmd+Mellomrom, skriv «Terminal»), lim inn
linja du har fått fra AIKI, og trykk Enter:

```
curl -fsSL https://raw.githubusercontent.com/AIKI-AS/aiki-referat-dist/main/scripts/install.sh | bash -s -- --calendar-key DIN-NØKKEL
```

Det er alt. Du trenger ikke installere noe på forhånd — `curl` følger med
macOS. Appen legger seg i Programmer og er ferdig konfigurert.

Første gang laster den ned språkmodellene (rundt 3 GB), så sett av litt tid.

## Oppdater senere

```
aiki-referat update
```

## Hvis du helst vil unngå Terminal

Last ned `.dmg`-fila fra [siste utgivelse](../../releases/latest), åpne den og
dra appen til Programmer.

macOS vil da blokkere appen første gang, fordi den ennå ikke er notarisert hos
Apple. Slik åpner du den likevel:

1. Prøv å åpne appen. Du får en melding om at den ikke kan åpnes.
2. Gå til **Systeminnstillinger → Personvern og sikkerhet**.
3. Bla ned. Der står det at «AIKI Referat» ble blokkert. Trykk **Åpne likevel**.
4. Bekreft med passord eller Touch ID.

Du gjør dette én gang. Terminal-kommandoen over hopper over hele dette steget,
og er derfor den vi anbefaler.

*Merk: du må da også legge inn nøkkelen din manuelt under Innstillinger.*

## Hva appen gjør på maskinen din

| | |
|---|---|
| Tar opp møtet | Lokalt |
| Gjør tale om til tekst | Lokalt (NB-Whisper fra Nasjonalbiblioteket) |
| Skiller mellom talere | Lokalt |
| Skriver referatet | Lokalt |
| Lagrer opptak og referat | Lokalt, i mappa `~/aiki-referat` |
| Sjekker kalenderen for møter | AIKIs server — kun møtetittel og tidspunkt |

## Trenger du hjelp?

jonathan@aiki.as

---

Dette repoet inneholder kun installasjonsscriptet og ferdige utgivelser.
Kildekoden er privat.

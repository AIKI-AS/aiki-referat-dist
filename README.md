# AIKI Meetings — installasjon

Møtenotattaker som tar opp og transkriberer lokalt på din Mac. Når automatisk
referat er aktivert, sendes transkript og talernavn kryptert til AIKIs
referattjeneste. Lyd sendes ikke til referattjenesten.

Krever en Mac med Apple Silicon (M1 eller nyere) og macOS 14.4 eller nyere.

---

## Installer

Åpne **Terminal** — trykk Cmd+Mellomrom, skriv «Terminal», trykk Enter.

Lim inn denne linja og trykk Enter:

```
curl -fsSL https://referat.aiki.as/install | bash
```

Du blir bedt om å lime inn nøkkelen du har fått av AIKI. Gjør det, trykk
Enter, og resten går av seg selv.

Det er alt. Du trenger ikke installere noe på forhånd — `curl` følger med
macOS. Appen legger seg i Programmer og er ferdig konfigurert.

Første gang laster den ned språkmodellene (rundt 3 GB), så sett av litt tid.

## Oppdater senere

```
aiki-meetings update
```

## Hvis du helst vil unngå Terminal

Last ned `.dmg`-fila fra [siste utgivelse](../../releases/latest), åpne den og
dra appen til Programmer.

Utgivelser publiseres først når signatur, Gatekeeper og notarization er
verifisert. Hvis macOS avviser appen, ikke overstyr sikkerhetsvarselet; kontakt
AIKI. Ved manuell installasjon må kundenøkkelen legges inn under Innstillinger.

## Hva appen gjør på maskinen din

| | |
|---|---|
| Tar opp møtet | Lokalt |
| Gjør tale om til tekst | Lokalt (NB-Whisper fra Nasjonalbiblioteket) |
| Skiller mellom talere | Lokalt |
| Skriver referatet | AIKIs EU-baserte referattjeneste, når aktivert |
| Lagrer opptak, transkript og referat | Lokalt på Mac-en |
| Sjekker kalenderen for møter | AIKIs server — kun møtetittel og tidspunkt |

## Trenger du hjelp?

jonathan@aiki.as

---

Dette repoet inneholder kun installasjonsscriptet og ferdige utgivelser.
Kildekoden er privat.

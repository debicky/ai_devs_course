---
title: S03E01 — Obserwowanie i ewaluacja
space_id: 2476415
status: scheduled
published_at: '2026-03-23T04:00:00Z'
is_comments_enabled: true
is_liking_enabled: true
skip_notifications: false
cover_image: 'https://cloud.overment.com/evals-1773910362.png'
circle_post_id: 30844594
---
## Film do lekcji

![https://vimeo.com/1175527097](https://vimeo.com/1175527097)

Nawet najmniejsze zmiany w instrukcji systemowej, opisie narzędzi czy formacie odpowiedzi mogą znacząco wpływać na zachowanie systemu. W przypadku prostych promptów relatywnie łatwo możemy dostrzec problemy i je naprawić. Sytuacja komplikuje się, gdy w ich treści pojawiają się dynamiczne dane, a struktura składa się z wielu modułów. Jeśli dołożymy do tego kontekst konwersacji, a potem rozgałęzienia w aktywnościach wielu agentów, wyzwaniem staje się nawet przeczytanie treści zapytania do API.

W tym miejscu wchodzą do gry narzędzia do ewaluacji zachowań agentów oraz ich monitorowania w sposób wykraczający poza podstawowe logowanie zdarzeń.

Poza tym sama ewaluacja może odbywać się nie tylko **przed publikacją** (offline eval), ale także **w trakcie działania aplikacji** (online eval).

Do pełnego obrazu na tym etapie musimy dodać także Guardrails, czyli mechaniki związane z moderacją i filtrowaniem treści oraz blokowaniem niepożądanych zapytań.

## Zasady monitorowania zachowań modelu

- **Session:** zwykle powiązana z wątkiem (np. czatu) bądź zadaniami agentów.
- **Trace:** zwykle pojedyncza interakcja użytkownika (np. wiadomość czatu)
- **Span:** dotyczy czasu trwania wybranych akcji (np. gromadzenie kontekstu)
- **Generation:** to interakcja z LLM, obejmuje cały kontekst zapytania i ustawienia
- **Agent:** obejmuje działanie agenta w trakcie interakcji
- **Tool:** obejmuje uruchomienie narzędzia (input/output)
- **Event:** obejmuje zdarzenia z aplikacji, niekoniecznie powiązane z LLM

## Narzędzia do ewaluacji

- [Langfuse](https://langfuse.com/)
- [Promptfoo](https://www.promptfoo.dev/)
- [Confident AI](https://www.confident-ai.com/)
- [Braintrust](https://www.braintrust.dev/)
- [Grafana](https://grafana.com/)

## Fabuła

> Numerze piąty! Znowu mi zaimponowałeś. Mamy już wodę.
>
> Teraz skupimy się na problemie firmware'u. Mamy prawie 10 tysięcy odczytów z różnych sensorów:
> czujniki wody, temperatury, napięcia, ciśnienia i jeszcze jakieś mieszane. Część z tych danych
> jest po prostu błędna, a Ty musisz powiedzieć, które to są.

## Zadanie

Znalezienie anomalii w odczytach sensorów.

Czujniki zwracają dane w formacie:

```json
{
  "sensor_type": "temperature/voltage",
  "timestamp": 1774064280,
  "temperature_K": 612,
  "pressure_bar": 0,
  "water_level_meters": 0,
  "voltage_supply_v": 230.4,
  "humidity_percent": 0,
  "operator_notes": "Readings look stable and within expected range."
}
```

**Nazwa zadania: `evaluation`**

Dane: `https://hub.ag3nts.org/dane/sensors.zip`

### Zakres poprawnych wartości

| Pole | Min | Max |
|---|---|---|
| `temperature_K` | 553 | 873 |
| `pressure_bar` | 60 | 160 |
| `water_level_meters` | 5.0 | 15.0 |
| `voltage_supply_v` | 229.0 | 231.0 |
| `humidity_percent` | 40.0 | 80.0 |

### Anomalie do wykrycia

1. Dane pomiarowe poza zakresem norm
2. Operator twierdzi OK, ale dane są niepoprawne
3. Operator twierdzi, że błędy, ale dane są OK
4. Czujnik zwraca dane, których nie powinien (np. water sensor z niezerowym voltage)

### Format odpowiedzi

```json
{
  "apikey": "...",
  "task": "evaluation",
  "answer": {
    "recheck": ["0001", "0002", "0003", "..."]
  }
}
```

### Wskazówki

- 10 000 plików — nie wrzucaj wszystkiego do LLM, to drogie
- Podpowiedź (Base64): `RHdpZSBwb2Rwb3dpZWR6aToKMSkgTExNLXkgbWFqxIUgc3fDs2ogY2FjaGUsIGFsZSBUeSB0YWvFvGUgbW/FvGVzeiBjYWNob3dhxIcgb2Rwb3dpZWR6aSBtb2RlbHUgcG8gc3dvamVqIHN0cm9uaWUuIEN6eSBuaWVrdMOzcmUgZGFuZSBuaWUgc8SFIHpkdXBsaWtvd2FuZT8KMikgQ3p5IHByemVwcm93YWR6ZW5pZSBrbGFzeWZpa2Fjamkgd3N6eXN0a2ljaCBkYW55Y2ggcHJ6ZXogbW9kZWwgasSZenlrb3d5IGLEmWR6aWUgb3B0eW1hbG5lIGtvc3p0b3dvPyBCecSHIG1vxbxlIGN6xJnFm8SHIGRhbnljaCBkYSBzacSZIG9kcnp1Y2nEhyBwcm9ncmFtaXN0eWN6bmllPw==`
- Parte anomalii wykryj programistycznie (zakres wartości, błędne pola), resztę przez LLM (operator_notes)
- Technicy są leniwi — wiele notatek się powtarza → cache odpowiedzi LLM po stronie klienta
- Minimalizuj output modelu: wysyłaj wiele rekordów naraz, model zwraca tylko ID anomalii


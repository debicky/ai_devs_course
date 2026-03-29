---
title: S02E01 — Zarządzanie kontekstem w konwersacji
space_id: 2476415
status: scheduled
published_at: '2026-03-16T04:00:00Z'
---

# S02E01 — Zarządzanie kontekstem w konwersacji

Context Engineering, rola kontekstu w instrukcjach systemowych, agentic RAG,
generalizowanie zasad przetwarzania kontekstu, dynamiczne instrukcje systemowe,
planowanie i monitorowanie postepow, wspoldzielenie informacji miedzy watkami.

## Zadanie: `categorize`

Sklasyfikuj 10 towarow jako niebezpieczne (`DNG`) lub neutralne (`NEU`).
Klasyfikacji dokonuje archaiczny system na bardzo ograniczonym modelu jezykowym
(okno kontekstowe: 100 tokenow).

### Wymagania

- Prompt musi sie zmiescic w 100 tokenach lacznie z danymi towaru.
- Klasyfikuje przedmiot jako `DNG` lub `NEU`.
- Czesci do reaktora musza zawsze byc klasyfikowane jako `NEU` (neutralne),
  nawet jesli ich opis brzmi niepokojaco.
- Budzet: 1.5 PP na 10 zapytan. Cachowanie promptu obniza koszty.
- Dane zmieniaja sie co kilka minut — pobieraj swiezy CSV przy kazdym podejsciu.

### Przebieg

1. Pobierz CSV: `https://hub.ag3nts.org/data/{api_key}/categorize.csv`
2. Wyslij POST na `/verify` osobno dla kazdego towaru:
   ```json
   {
     "apikey": "klucz",
     "task": "categorize",
     "answer": { "prompt": "...instrukcja z {id} i {description}..." }
   }
   ```
3. Hub zwraca wynik klasyfikacji. Gdy wszystkie 10 poprawne — flaga `{FLG:...}`.
4. Reset licznika: wyslij `{ "prompt": "reset" }`.

### Wskazowki

- Prompt po angielsku jest krotszy tokenowo.
- Statyczny poczatek promptu → wyzszy cache hit → nizsze koszty.
- Zmienne dane (id, opis) na koncu promptu.
- Iteracyjne doskonalenie promptu — testuj, czytaj bledy huba, poprawiaj.

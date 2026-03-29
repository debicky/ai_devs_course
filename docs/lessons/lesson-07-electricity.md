---
title: S02E02 — Zewnetrzny kontekst narzedzi i dokumentow
published_at: '2026-03-17T04:00:00Z'
---

# S02E02 — Zewnetrzny kontekst narzedzi i dokumentow

Context engineering for external data: security of external context, RAG systems,
indexing strategies, semantic search with embeddings, hybrid search (FTS + vector),
retrieval techniques, and challenges of connecting LLMs to external knowledge bases.

## Zadanie: `electricity`

Puzzle elektryczne na planszy 3x3 — doprowadz prad do trzech elektrowni
(PWR6132PL, PWR1593PL, PWR7264PL) obracajac pola z kablami.

### Wymagania

- Pobierz aktualny stan planszy jako PNG.
- Porownaj z docelowym ukladem (solved_electricity.png).
- Jedyna operacja: obrot pola o 90 stopni w prawo.
- Kazdy obrot = jedno zapytanie POST do `/verify`.
- Pola adresowane jako `AxB` (wiersz x kolumna, od 1).
- Gdy plansza poprawna — flaga `{FLG:...}`.

### Przebieg

1. Reset planszy: GET `.../electricity.png?reset=1`
2. Pobierz PNG, uzyj modelu vision do opisu kazdego pola (kierunki kabli).
3. Pobierz/przeanalizuj docelowy uklad.
4. Oblicz ile obrotow (0-3) potrzebuje kazde pole.
5. Wyslij obroty POST `/verify` z `{ "rotate": "AxB" }`.
6. Zweryfikuj wynik — pobierz swiezy PNG i porownaj.
7. Powtorz jesli trzeba.

### Wskazowki

- Model vision do analizy PNG (np. gpt-4o, gemini-3-flash-preview).
- Mozna podzielic obraz na 9 pol i analizowac kazde osobno.
- Kazde pole ma kable wychodzace przez kombinacje krawedzi (L/R/U/D).
- Obrot przesuwa krawedzie zgodnie z ruchem wskazowek zegara.
- 3 obroty w prawo = 1 obrot w lewo.

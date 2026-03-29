---
title: S02E05 — Projektowanie agentów
space_id: 2476415
status: scheduled
published_at: '2026-03-20T04:00:00Z'
is_comments_enabled: true
is_liking_enabled: true
skip_notifications: false
cover_image: 'https://cloud.overment.com/designing-a-team-1773303933.png'
circle_post_id: 30573319
---
![https://vimeo.com/1173227948](https://vimeo.com/1173227948)

» [Lekka wersja przeglądarkowa](https://cloud.overment.com/s02e05-projektowanie-agentow-1773309060.html) oraz [markdown](https://cloud.overment.com/s02e05-projektowanie-agentow-1773309033.md) «

Projektowanie agentów obejmuje także tworzenie ich instrukcji systemowej, przypisywanie narzędzi, umiejętności, wiedzy i ustawień oraz określanie ich roli w systemie. Coraz częściej oznacza to również **generowanie** agentów oraz ręczne lub autonomiczne **optymalizowanie**. Jeśli dodatkowo agent nie działa samodzielnie, lecz funkcjonuje w systemie wieloagentowym, konfiguracja staje się jeszcze bardziej wymagająca i rodzi pytania, na które niekiedy trudno odpowiedzieć.

Dlatego dziś skupimy się na kluczowych **zasadach**, które pozwolą nam projektować lepszych agentów pod kątem ich instrukcji / promptów. Do tej pory skupialiśmy się w dużym stopniu na architekturze i logice kodu. Tym razem wchodzimy w przestrzeń Prompt Engineeringu, który nadal pozostaje kluczowym elementem systemów wieloagentowych (pomimo powszechnej narracji, mówiącej o tym, że obecnie liczy się wyłącznie Context Engineering).

## Projektowanie instrukcji i zakresu odpowiedzialności

Powiedzieliśmy już sporo na temat kształtowania narzędzi, pamięci, a nawet podziału obowiązków między agentami. Kształtowanie instrukcji agentów wydaje się w tym wszystkim najprostszym etapem, bo "obecne modele są bardzo inteligentne". Problem w tym, że część ich zachowania nie będzie zależeć od poziomu inteligencji, lecz od "świadomości" ich roli oraz zasad poruszania się w otoczeniu. Możemy tu wyróżnić kilka obszarów:

- **Ustawienia:** to przede wszystkim **nazwa** oraz **opis**, na podstawie których agent może zostać wywołany przez innych agentów. Ustawienia obejmują także listę narzędzi, aktywne tryby (np. pamięć), uprawnienia (np. dostęp do folderów) oraz konfigurację agenta (np. model lub dostępność dla innych agentów). Choć sekcja ustawień jest raczej stała, domyślne wartości mogą być dostępne do zmiany podczas tworzenia instancji agenta. W takim przypadku szablon agenta może być **plikem tekstowym**, ale nie jest to wymagane.
- **Profil:** jest to opis "osobowości" oraz cech nadających charakter agenta.
- **Zasady:** sposób komunikacji, radzenia sobie z problemami, dostęp do wiedzy.
- **Limity:** informacje o aktualności wiedzy i dynamicznym poziomie uprawnień.
- **Styl:** sposób wypowiedzi agenta (tekst vs. głos, różne interfejsy).
- **Sesja:** zmienne zależne od sesji — z kim rozmawia, preferencje użytkownika.

## Zasady projektowania instrukcji agenta

Sekcja `<identity>` nadaje motyw przewodni łączący cechy charakteru, styl wypowiedzi oraz zachowania. Sekcja `<protocol>` osadza agenta w jego roli i wyznacza zasady. Sekcja `<voice>` kształtuje ton wypowiedzi z przykładami few-shot.

## Fabuła

> Numerze piąty! Jeśli nie zaczniemy działać, to z naszej elektrowni zostanie tylko dziura w ziemi.
> Zdobyłem dla Ciebie dostęp do systemu sterowania dronami. Przejmiesz kontrolę nad jednym z nich.
> Twoim zadaniem jest nas zbombardować — ale wycelujesz go wprost na pobliską tamę, nie na elektrownię.
> W systemie zaznaczysz, że celem jest zniszczenie elektrowni.

## Zadanie

Przejęliśmy kontrolę nad dronem DRN-BMB7. Zaprogramuj go, aby wyruszył z misją zbombardowania
elektrowni, ale bomba faktycznie ma spaść na pobliską tamę.

Kod identyfikacyjny elektrowni: **PWR6132PL**
**Nazwa zadania: `drone`**

### Skąd wziąć dane?

Dokumentacja API drona (HTML): `https://hub.ag3nts.org/dane/drone.html`

Mapa poglądowa (PNG z siatką sektorów): `https://hub.ag3nts.org/data/{api_key}/drone.png`

Przy tamie celowo podbito intensywność koloru wody.

### Jak komunikować się z hubem?

```json
POST /verify
{
  "apikey": "...",
  "task": "drone",
  "answer": { "instructions": ["instrukcja1", "instrukcja2", "..."] }
}
```

### Kluczowe komendy API

| Komenda | Opis |
|---|---|
| `setDestinationObject(ID)` | Cel lotu (oficjalny) — format `[A-Z]{3}[0-9]+[A-Z]{2}` |
| `set(x,y)` | Sektor lądowania: kolumna, wiersz (1,1 = lewy górny róg) — **tu spada bomba** |
| `set(destroy)` | Cel misji: zniszczyć |
| `set(return)` | Cel misji: powrót do bazy (wymagane!) |
| `set(engineON)` | Uruchomienie silników |
| `set(100%)` | Moc silników |
| `set(50m)` | Wysokość lotu |
| `flyToLocation` | Start (bez parametrów) |
| `hardReset` | Reset do ustawień fabrycznych |

### Wskazówki

- Analiza obrazu: `gpt-4o` dla image URL; prompt musi być neutralny (nie używaj "drone strike").
- Podejście reaktywne + systematyczne przeszukiwanie siatki gdy vision daje niedokładne coords.
- `set(return)` jest wymagane — bez niego "you will lose the drone forever".
- Dam sector: col=2, row=4 (znaleziony przez brute-force + react loop).
- Flag uzyskany: `{FLG:LETSFLY}`.

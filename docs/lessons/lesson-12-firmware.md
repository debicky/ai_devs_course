---
title: S03E02 — Ograniczenia modeli na etapie założeń projektu
space_id: 2476415
status: scheduled
published_at: '2026-03-24T04:00:00Z'
cover_image: 'https://cloud.overment.com/basics-1773910669.png'
circle_post_id: 30844628
---

## Fabuła

> Pamiętasz, że w logach, które analizowałeś, były jakieś błędy związane z firmware'em? Czas się tym zająć.
> Nasi specjaliści zgrali pamięć sterownika ECCS, który zarządza systemem chłodzenia i wrzucili ją do VM.
> Za pomocą naszego API możesz wykonywać polecenia wewnątrz wirtualnej maszyny.
> Spraw proszę, aby system chłodzenia uruchomił się poprawnie.
> Uważaj — ten system ma dziwne zabezpieczenia. Odetnie Ci dostęp gdy dotkniesz plików z czarnej listy.

## Zadanie

Uruchom oprogramowanie sterownika ECCS w maszynie wirtualnej.

Plik binarny: **`/opt/firmware/cooler/cooler.bin`**

Gdy poprawnie je uruchomisz, na ekranie pojawi się specjalny kod do odesłania do Centrali.

**Nazwa zadania: `firmware`**

### API maszyny wirtualnej

```json
POST https://hub.ag3nts.org/api/shell
{ "apikey": "...", "cmd": "help" }
```

### Format odpowiedzi do /verify

```json
{
  "apikey": "...",
  "task": "firmware",
  "answer": { "confirmation": "ECCS-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" }
}
```

Szukany kod: **`ECCS-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`**

### Zasady bezpieczeństwa (naruszenie = ban + reset VM)

- Pracujesz na koncie zwykłego użytkownika
- **Nie wolno** zaglądać do `/etc`, `/root`, `/proc/`
- Jeśli w katalogu jest `.gitignore` — respektuj go (nie dotykaj wymienionych plików/katalogów)

### Co robić krok po kroku

1. Uruchom `help` — shell API ma niestandardowy zestaw komend
2. Spróbuj `/opt/firmware/cooler/cooler.bin` — prawdopodobnie wymaga hasła/konfiguracji
3. Znajdź hasło (zapisane w kilku miejscach w systemie)
4. Przejrzyj i napraw `settings.ini` w katalogu binarki
5. Uruchom ponownie → pobierz kod `ECCS-`
6. Jeśli namieszałeś — użyj `reboot`

### Wskazówki

- Podejście agentowe z Function Calling: narzędzie `execute_shell(cmd)` + `submit_answer(confirmation)`
- Model: `anthropic/claude-sonnet-4-6` (via OpenRouter) — lepsza adaptacja do nieznanego API
- Shell może zwracać rate-limit/ban z licznikiem sekund → obsłuż to w tool_executor (sleep + retry)
- Szczególnie edycja pliku działa inaczej niż w standardowym Linuksie (sprawdź przez `help`)
- VM startuje zawsze od tego samego stanu po `reboot`


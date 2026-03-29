# AI Devs Course Tasks

Minimal Ruby app with small, explicit layers for AG3NTS tasks.

Lesson mapping:

### Week 1

- Lesson 1: `bin/week_1/run_1` (`people`)
- Lesson 2: `bin/week_1/find_him_2` (`findhim`)
- Lesson 3: `bin/week_1/proxy_3` (`proxy`)
- Lesson 4: `bin/week_1/sendit_4` (`sendit`)
- Lesson 5: `bin/week_1/railway_5` (`railway`)

### Week 2

- Lesson 6: `bin/week_2/categorize_6` (`categorize`)
- Lesson 7: `bin/week_2/electricity_7` (`electricity`)

## Lesson notes

Source lesson markdowns are stored in `docs/lessons/` for quick reference:

- Lesson 1 / `people` / `bin/week_1/run_1` → [`docs/lessons/lesson-01-people.md`](docs/lessons/lesson-01-people.md)
- Lesson 2 / `findhim` / `bin/week_1/find_him_2` → [`docs/lessons/lesson-02-find-him.md`](docs/lessons/lesson-02-find-him.md)
- Lesson 3 / `proxy` / `bin/week_1/proxy_3` → [`docs/lessons/lesson-03-proxy.md`](docs/lessons/lesson-03-proxy.md)
- Lesson 4 / `sendit` / `bin/week_1/sendit_4` → [`docs/lessons/lesson-04-sendit.md`](docs/lessons/lesson-04-sendit.md)
- Lesson 5 / `railway` / `bin/week_1/railway_5` → [`docs/lessons/lesson-05-railway.md`](docs/lessons/lesson-05-railway.md)
- Lesson 6 / `categorize` / `bin/week_2/categorize_6` → [`docs/lessons/lesson-06-categorize.md`](docs/lessons/lesson-06-categorize.md)
- Lesson 7 / `electricity` / `bin/week_2/electricity_7` → [`docs/lessons/lesson-07-electricity.md`](docs/lessons/lesson-07-electricity.md)

## Structure

```text
bin/
  week_1/
    run_1                         # Lesson 1: people task entrypoint
    find_him_2                    # Lesson 2: findhim task entrypoint
    proxy_3                       # Lesson 3: proxy HTTP server entrypoint
    sendit_4                      # Lesson 4: sendit declaration entrypoint
    railway_5                     # Lesson 5: railway task entrypoint
  week_2/
    categorize_6                  # Lesson 6: categorize task entrypoint
    electricity_7                 # Lesson 7: electricity puzzle entrypoint
docs/
  lessons/
    lesson-01-people.md           # lesson note / source material
    lesson-02-find-him.md         # lesson note / source material
    lesson-03-proxy.md            # lesson note / source material
    lesson-04-sendit.md           # lesson note / source material
    lesson-05-railway.md          # lesson note / source material
    lesson-06-categorize.md       # lesson note / source material (week 2)
    lesson-07-electricity.md      # lesson note / source material (week 2)
config/
  environment.rb                  # bootstrap and require order
app/
  clients/
    http_client.rb                # shared Net::HTTP wrapper
    hub_client.rb                 # AG3NTS Hub API client
    llm_client.rb                 # LLM JSON schema + tool-calling client
    packages_client.rb            # package API client
  s01/                            # Week 1
    services/
      people/
        csv_parser.rb
        filter.rb
        job_classifier.rb
        transport_selector.rb
        answer_builder.rb
      find_him/
        suspects_loader.rb        # load suspects from local JSON
        distance_calculator.rb    # Haversine distance
        tool_executor.rb          # executes LLM-requested tools
      proxy/
        session_store.rb          # per-session memory on disk
        tool_executor.rb          # package tools requested by the LLM
        conversation_runner.rb    # bounded function-calling loop
        http_server.rb            # local JSON endpoint
      send_it/
        documentation_explorer.rb # recursive SPK docs discovery with image OCR
        declaration_builder.rb    # derive and fill the declaration form
      railway/
        runner.rb                 # resilient railway API state machine
    tasks/
      people_task.rb
      find_him_task.rb
      proxy_task.rb
      sendit_task.rb
      railway_task.rb
  s02/                            # Week 2
    services/
      categorize/
        runner.rb                 # prompt-engineering classifier loop
      electricity/
        board_reader.rb           # vision-based PNG grid analysis
        rotation_solver.rb        # compute rotations from current to target
        runner.rb                 # orchestrate: read, solve, rotate, verify
    tasks/
      categorize_task.rb
      electricity_task.rb
data/
  suspects.json                   # suspects from previous task output
  proxy_sessions/                 # generated session history, gitignored
```

## Environment variables

`.env` should contain secrets only:

```bash
AG3NTS_API_KEY=your_ag3nts_key
OPENAI_API_KEY=your_openai_key
# optional for other flows
GEMINI_API_KEY=your_gemini_key
```

Model selection stays in each run file. You can override it temporarily with `LLM_MODEL`.

### Which script uses which keys?

- `bin/week_1/run_1`
  - requires `AG3NTS_API_KEY`
  - uses `GEMINI_API_KEY` if present
  - otherwise falls back to `OPENAI_API_KEY`
- `bin/week_1/find_him_2`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`
- `bin/week_1/proxy_3`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`
  - optional `PORT` (default `3000`)
- `bin/week_1/sendit_4`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`
- `bin/week_1/railway_5`
  - requires `AG3NTS_API_KEY`
- `bin/week_2/categorize_6`
  - requires `AG3NTS_API_KEY`

## Lesson 1 / Task 1: `people` (`bin/week_1/run_1`)

This is the first task / lesson.

What `bin/week_1/run_1` does:

1. downloads `people.csv`
2. parses and filters the records
3. classifies jobs in one batch LLM request
4. keeps only transport-related people
5. sends the final answer to `/verify`
6. saves the selected suspects to `data/suspects.json` for the next task

Run it with:

```bash
bundle install
chmod +x bin/week_1/run_1 bin/week_1/find_him_2
bin/week_1/run_1
```

After it finishes you should have:

- verification output for the `people` task
- a terminal summary of transport suspects
- `data/suspects.json` generated automatically

## Lesson 2 / Task 2: `find_him` (`bin/week_1/find_him_2`)

This is the second task / lesson.

`bin/week_1/find_him_2` uses the suspects saved by `bin/week_1/run_1` in `data/suspects.json` and then:

1. loads suspects from `data/suspects.json`
2. checks where each suspect was seen
3. finds which suspect was seen closest to a nuclear power plant
4. fetches that person's access level
5. submits the final answer to `/verify`

Run it with:

```bash
bin/week_1/find_him_2
```

## Lesson 3 / Task 3: `proxy` (`bin/week_1/proxy_3`)

This task starts a local HTTP endpoint for a transparent logistics assistant.

What `bin/week_1/proxy_3` does:

1. starts a local HTTP server
2. accepts `POST /` JSON requests with `sessionID` and `msg`
3. keeps separate conversation history per session in `data/proxy_sessions/`
4. uses an LLM with function calling
5. can check package status and redirect a package exactly to the operator-requested destination
6. returns JSON only in the form `{ "msg": "..." }`

Run it with:

```bash
chmod +x bin/week_1/proxy_3
bin/week_1/proxy_3
```

You can override the port:

```bash
PORT=4000 bin/week_1/proxy_3
```

Request format:

```json
{
  "sessionID": "demo-1",
  "msg": "Sprawdź paczkę PKG12345678"
}
```

Response format:

```json
{
  "msg": "Już sprawdzam status tej paczki."
}
```

Example local request:

```bash
curl -X POST http://localhost:3000/ \
  -H 'Content-Type: application/json' \
  -d '{"sessionID":"demo-1","msg":"Sprawdź paczkę PKG12345678"}'
```

For public testing, you can expose the local server with a tunnel such as `ngrok`.

### Debugging package API issues

If package checks or redirects return unexpected results, test the external package API directly to distinguish:

- invalid package ID or redirect code
- external API behavior
- bug in your app

Conceptually, compare the direct API response with the logs from `bin/week_1/proxy_3`.

Check example:

```bash
curl -X POST https://hub.ag3nts.org/api/packages \
  -H 'Content-Type: application/json' \
  -d '{"apikey":"YOUR_AG3NTS_API_KEY","action":"check","packageid":"PKG12345678"}'
```

Redirect example:

```bash
curl -X POST https://hub.ag3nts.org/api/packages \
  -H 'Content-Type: application/json' \
  -d '{"apikey":"YOUR_AG3NTS_API_KEY","action":"redirect","packageid":"PKG12345678","destination":"PWR3847PL","code":"YOUR_CODE"}'
```

The proxy logs now include:

- tool-call arguments (`packageid`, `destination`, `code`)
- package API action name
- outbound payload with redacted `apikey`
- raw response body from the external API

This makes it easier to verify whether the model changed arguments or whether the external API rejected valid-looking test data.

## Lesson 4 / Task 4: `sendit` (`bin/week_1/sendit_4`)

This task generates the SPK transport declaration for the `sendit` challenge and submits it to `/verify`.

What `bin/week_1/sendit_4` does:

1. fetches the public SPK documentation index
2. recursively follows linked markdown and `[include file="..."]` attachments
3. uses a vision-capable LLM path for image attachments like `trasy-wylaczone.png`
4. extracts the exact declaration template from `zalacznik-E.md`
5. finds the blocked route code for `Gdańsk -> Żarnowiec`
6. fills the declaration with the required sender, weight, content, WDP, and zero-cost amount
7. sends `{ "declaration": "..." }` to `/verify` for task `sendit`

Run it with:

```bash
chmod +x bin/week_1/sendit_4
bin/week_1/sendit_4
```

Notes:

- `bin/week_1/sendit_4` keeps model selection in the file itself and defaults to `gpt-4o-mini`.
- The declaration is printed before verification so you can inspect the final paper-form string.
- The implementation derives the Żarnowiec route from the documentation instead of hardcoding the route code.

## Lesson 5 / Task 5: `railway` (`bin/week_1/railway_5`)

This task interacts with the self-documenting railway API and activates route `X-01`.

What `bin/week_1/railway_5` does:

1. starts with `action: "help"`
2. validates the returned action list
3. checks the current status of route `X-01`
4. enters reconfigure mode if needed
5. sets the route status to `RTOPEN`
6. saves the configuration and waits for the flag response
7. logs every request, response body, and response header for debugging
8. automatically handles `503` with exponential backoff and respects the strict request window / retry headers

Run it with:

```bash
chmod +x bin/week_1/railway_5
bin/week_1/railway_5
```

Notes:

- `bin/week_1/railway_5` does not require an LLM.
- The API is intentionally unstable and aggressively rate-limited, so the runner is conservative and may wait between calls.
- The task is complete only when the response contains a flag like `{FLG:...}`.

## Lesson 6 / Task 6: `categorize` (`bin/week_2/categorize_6`)

This task classifies 10 items as dangerous (`DNG`) or neutral (`NEU`) via a token-constrained prompt.

What `bin/week_2/categorize_6` does:

1. resets the hub budget counter
2. downloads fresh CSV from the hub (contents rotate every few minutes)
3. parses the 10 items (id + description)
4. builds a compact classification prompt (must fit in 100 tokens including item data)
5. sends the prompt for each item to `/verify` with task `categorize`
6. reactor-related items are always classified as `NEU` to avoid inspection
7. reads hub feedback — if a classification fails or budget runs out, resets and retries with an adjusted prompt
8. returns the flag when all 10 items pass

Run it with:

```bash
chmod +x bin/week_2/categorize_6
bin/week_2/categorize_6
```

Notes:

- The prompt is in English to save tokens.
- Static prompt prefix maximises cache hits (cheaper tokens).
- Variable data (item id, description) goes at the end of the prompt.
- `bin/week_2/categorize_6` does not require an LLM beyond the hub's internal model.

### `data/suspects.json`

You usually do not need to create this file manually anymore, because `bin/run` writes it for you.

The expected shape is still:

```json
[
  {
    "name": "Jan",
    "surname": "Kowalski",
    "born": 1987
  }
]
```

If `data/suspects.json` contains placeholder or stale data, `bin/week_1/find_him_2` will work on the wrong suspects.

## Quick-run examples

```bash
bundle install

# Week 1
bin/week_1/run_1           # Lesson 1: people
bin/week_1/find_him_2      # Lesson 2: findhim
bin/week_1/proxy_3         # Lesson 3: proxy server
bin/week_1/sendit_4        # Lesson 4: sendit
bin/week_1/railway_5       # Lesson 5: railway

# Week 2
bin/week_2/categorize_6    # Lesson 6: categorize
```

## Notes

- `people` uses one batch LLM classification request with structured JSON schema output.
- `findhim` intentionally uses Function Calling, with the model choosing which tool to call next.
- `proxy` also uses Function Calling, but only for transparent package operations (`check_package` and `redirect_package`).
- `sendit` uses recursive document discovery plus image text extraction to reconstruct the exact declaration string from the SPK docs.
- `railway` uses a deterministic state machine with raw header logging, exponential backoff for `503`, and cooldown handling for the API's strict limits.
- `bin/week_1/run_1` already saves `data/suspects.json`, so `find_him` can reuse the previous task output directly.
- `findhim` tools are bounded by a max-iteration loop and fail loudly on invalid API responses.
- `submit_answer` sends the final `findhim` answer to `/verify`.
- `proxy` keeps per-session history in `data/proxy_sessions/`, which is ignored by git.

# AI Devs Course Tasks

Minimal Ruby app with small, explicit layers for AG3NTS tasks.

Lesson mapping:

- Lesson 1: `bin/run` (`people`)
- Lesson 2: `bin/find_him` (`findhim`)
- Lesson 3: `bin/proxy` (`proxy`)
- Lesson 4: `bin/sendit` (`sendit`)

## Structure

```text
bin/
  run                             # Lesson 1: people task entrypoint
  find_him                        # Lesson 2: findhim task entrypoint
  proxy                           # Lesson 3: proxy HTTP server entrypoint
  sendit                          # Lesson 4: sendit declaration entrypoint
config/
  environment.rb                  # bootstrap and require order
app/
  clients/
    http_client.rb                # shared Net::HTTP wrapper
    hub_client.rb                 # AG3NTS Hub API client
    llm_client.rb                 # LLM JSON schema + tool-calling client
    packages_client.rb            # package API client
  services/
    people/
      csv_parser.rb
      filter.rb
      job_classifier.rb
      transport_selector.rb
      answer_builder.rb
    find_him/
      suspects_loader.rb          # load suspects from local JSON
      distance_calculator.rb      # Haversine distance
      tool_executor.rb            # executes LLM-requested tools
    proxy/
      session_store.rb            # per-session memory on disk
      tool_executor.rb            # package tools requested by the LLM
      conversation_runner.rb      # bounded function-calling loop
      http_server.rb              # local JSON endpoint
    send_it/
      documentation_explorer.rb   # recursive SPK docs discovery with image OCR
      declaration_builder.rb      # derive and fill the declaration form
  tasks/
    people_task.rb
    find_him_task.rb
    proxy_task.rb
    sendit_task.rb
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

- `bin/run`
  - requires `AG3NTS_API_KEY`
  - uses `GEMINI_API_KEY` if present
  - otherwise falls back to `OPENAI_API_KEY`
- `bin/find_him`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`
- `bin/proxy`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`
  - optional `PORT` (default `3000`)
- `bin/sendit`
  - requires `AG3NTS_API_KEY`
  - requires `OPENAI_API_KEY`

## Lesson 1 / Task 1: `people` (`bin/run`)

This is the first task / lesson.

What `bin/run` does:

1. downloads `people.csv`
2. parses and filters the records
3. classifies jobs in one batch LLM request
4. keeps only transport-related people
5. sends the final answer to `/verify`
6. saves the selected suspects to `data/suspects.json` for the next task

Run it with:

```bash
bundle install
chmod +x bin/run bin/find_him
bin/run
```

After it finishes you should have:

- verification output for the `people` task
- a terminal summary of transport suspects
- `data/suspects.json` generated automatically

## Lesson 2 / Task 2: `find_him` (`bin/find_him`)

This is the second task / lesson.

`bin/find_him` uses the suspects saved by `bin/run` in `data/suspects.json` and then:

1. loads suspects from `data/suspects.json`
2. checks where each suspect was seen
3. finds which suspect was seen closest to a nuclear power plant
4. fetches that person's access level
5. submits the final answer to `/verify`

Run it with:

```bash
bin/find_him
```

## Lesson 3 / Task 3: `proxy` (`bin/proxy`)

This task starts a local HTTP endpoint for a transparent logistics assistant.

What `bin/proxy` does:

1. starts a local HTTP server
2. accepts `POST /` JSON requests with `sessionID` and `msg`
3. keeps separate conversation history per session in `data/proxy_sessions/`
4. uses an LLM with function calling
5. can check package status and redirect a package exactly to the operator-requested destination
6. returns JSON only in the form `{ "msg": "..." }`

Run it with:

```bash
chmod +x bin/proxy
bin/proxy
```

You can override the port:

```bash
PORT=4000 bin/proxy
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

Conceptually, compare the direct API response with the logs from `bin/proxy`.

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

## Lesson 4 / Task 4: `sendit` (`bin/sendit`)

This task generates the SPK transport declaration for the `sendit` challenge and submits it to `/verify`.

What `bin/sendit` does:

1. fetches the public SPK documentation index
2. recursively follows linked markdown and `[include file="..."]` attachments
3. uses a vision-capable LLM path for image attachments like `trasy-wylaczone.png`
4. extracts the exact declaration template from `zalacznik-E.md`
5. finds the blocked route code for `Gdańsk -> Żarnowiec`
6. fills the declaration with the required sender, weight, content, WDP, and zero-cost amount
7. sends `{ "declaration": "..." }` to `/verify` for task `sendit`

Run it with:

```bash
chmod +x bin/sendit
bin/sendit
```

Notes:

- `bin/sendit` keeps model selection in the file itself and defaults to `gpt-4o-mini`.
- The declaration is printed before verification so you can inspect the final paper-form string.
- The implementation derives the Żarnowiec route from the documentation instead of hardcoding the route code.

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

If `data/suspects.json` contains placeholder or stale data, `bin/find_him` will work on the wrong suspects.

## Run both tasks in order

```bash
bundle install
chmod +x bin/run bin/find_him
bin/run
bin/find_him
```

## Run the sendit task

```bash
bundle install
chmod +x bin/sendit
bin/sendit
```

## Run the proxy server

```bash
bundle install
chmod +x bin/proxy
bin/proxy
```

## Notes

- `people` uses one batch LLM classification request with structured JSON schema output.
- `findhim` intentionally uses Function Calling, with the model choosing which tool to call next.
- `proxy` also uses Function Calling, but only for transparent package operations (`check_package` and `redirect_package`).
- `sendit` uses recursive document discovery plus image text extraction to reconstruct the exact declaration string from the SPK docs.
- `bin/run` already saves `data/suspects.json`, so `find_him` can reuse the previous task output directly.
- `findhim` tools are bounded by a max-iteration loop and fail loudly on invalid API responses.
- `submit_answer` sends the final `findhim` answer to `/verify`.
- `proxy` keeps per-session history in `data/proxy_sessions/`, which is ignored by git.

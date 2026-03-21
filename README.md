# AI Devs Course Tasks

Minimal Ruby app with small, explicit layers for AG3NTS tasks.

Lesson mapping:

- Lesson 1: `bin/run` (`people`)
- Lesson 2: `bin/find_him` (`findhim`)

## Structure

```text
bin/
  run                             # Lesson 1: people task entrypoint
  find_him                        # Lesson 2: findhim task entrypoint
config/
  environment.rb                  # bootstrap and require order
app/
  clients/
    http_client.rb                # shared Net::HTTP wrapper
    hub_client.rb                 # AG3NTS Hub API client
    llm_client.rb                 # LLM JSON schema + tool-calling client
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
  tasks/
    people_task.rb
    find_him_task.rb
data/
  suspects.json                   # suspects from previous task output
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

## Notes

- `people` uses one batch LLM classification request with structured JSON schema output.
- `findhim` intentionally uses Function Calling, with the model choosing which tool to call next.
- `bin/run` already saves `data/suspects.json`, so `find_him` can reuse the previous task output directly.
- `findhim` tools are bounded by a max-iteration loop and fail loudly on invalid API responses.
- `submit_answer` sends the final `findhim` answer to `/verify`.

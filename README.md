# People Task

Minimal, clean Ruby architecture for an AI course task.

## Structure

```
bin/run                          # Entry point
config/environment.rb            # Bootstrap: stdlib, dotenv, require order
app/
  clients/
    http_client.rb               # Net::HTTP wrapper (GET/POST JSON)
    hub_client.rb                # Fetch CSV + verify answer
    openai_client.rb             # Chat Completions with JSON schema output
  services/
    people/
      csv_parser.rb              # Parse + validate CSV headers strictly
      filter.rb                  # male + Grudziądz + age 20-40 in 2026
      job_classifier.rb          # Batch classify jobs via OpenAI
      transport_selector.rb      # Keep only transport-tagged records
      answer_builder.rb          # Build final JSON payload
  tasks/
    people_task.rb               # Orchestrate full pipeline
```

## Required environment variables

| Variable         | Required | Default      |
|------------------|----------|--------------|
| `AG3NTS_API_KEY` | Yes      | —            |
| `OPENAI_API_KEY` | Yes      | —            |
| `OPENAI_MODEL`   | No       | `gpt-4o-mini`|

Add them to `.env`:

```
AG3NTS_API_KEY=your_key_here
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
```

## Run

```bash
bundle install
chmod +x bin/run
bin/run
```

## Notes

- CSV parser validates exact header row and fails loudly on mismatch.
- All jobs are classified in a single OpenAI batch request.
- Structured output uses `response_format: { type: "json_schema" }`.
- Final answer excludes `job`, keeps `born` as integer, `tags` as array.


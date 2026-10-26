# Overrides

Tools are generated from Garmin's OpenAPI document ([`data/openapi.json`](../data/openapi.json)), which is the
source of truth for endpoints and parameters. Garmin's spec has no operation IDs and some descriptions are
thin, so [`data/overrides.yml`](../data/overrides.yml) refines it for assistants:

- a stable, readable **tool name** for every operation (matching Garmin's official Python client where it
  has an equivalent),
- better **descriptions** for tools and parameters,
- **required** flags the spec leaves out,
- **defaults** that keep responses small,
- **date range limits** that are checked before Garmin is called, so the assistant gets a clear error.

You can layer your own file on top with `GARMIN_MCP_OVERRIDES_FILE`, for example to reword a description for
your assistant. User overrides are merged per operation and per parameter.

## Format

```yaml
# Replaces the server instructions sent to clients at initialization.
instructions: |
  Read-only access to the user's own Garmin Connect data. ...

operations:
  # Keyed by HTTP method and path exactly as in the OpenAPI document.
  GET /sleep-service/sleep/dailySleepSummariesByDate:
    name: get_daily_sleep_summaries      # tool name: lowercase letters, digits, underscores
    title: Sleep summaries for a date range
    description: Replaces the description from the spec.
    description_append: Appended to the description (from the spec or the override above).
    enabled: true                        # false hides the tool unless GARMIN_MCP_TOOLS names it
    parameters:
      startDate:
        description: First calendar date of the range (YYYY-MM-DD), inclusive.
        required: true                   # override the spec's required flag
        hidden: false                    # true removes it from the tool; its default is always sent
  GET /activitylist-service/activities/search/activities:
    parameters:
      limit:
        default: 20                      # sent to Garmin when the argument is omitted (quote date strings)
    date_range:                          # validated before calling Garmin
      start: startDate
      end: endDate
      max_days: 31                       # also stated in the tool description
```

All keys are optional except that the bundled file must name every operation.

## Validation

Overrides are validated strictly when the server starts and in the test suite:

- unknown keys are rejected (a typo such as `nmae` fails instead of being ignored),
- every operation and parameter an override refers to must exist in the spec,
- tool names must be unique,
- the bundled file must give every operation in the spec a name.

When Garmin changes the spec, these checks point at exactly what needs attention. The
[`sync-garmin-openapi`](../.claude/skills/sync-garmin-openapi/SKILL.md) skill walks through the update.

## Reviewing the effect

`bin/garmin-mcp tools` prints every tool with its final name, description and input schema. The same
output is snapshotted in [`test/fixtures/tools.json`](../test/fixtures/tools.json), so every change to the spec
or overrides shows up as a reviewable diff. Regenerate it with `UPDATE_SNAPSHOTS=1 bundle exec rake test`.

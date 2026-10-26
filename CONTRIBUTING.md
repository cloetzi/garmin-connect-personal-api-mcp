# Contributing

Thanks for helping! Bug reports, spec refinements and fixes are all welcome.

## Setup

Requires Ruby 4.0 (see `.ruby-version`) and, for the image, Docker.

```sh
bundle install
bundle exec rake            # RuboCop and the test suite
bin/garmin-mcp tools        # print the generated tool catalog
```

Run the server locally against Garmin:

```sh
GARMIN_PERSONAL_API_KEY=... GARMIN_MCP_AUTH_TOKEN=$(openssl rand -hex 32) bin/garmin-mcp
```

Build and smoke-test the image:

```sh
docker build -t garmin-mcp:dev .
bin/docker-smoke-test garmin-mcp:dev
```

Tests never call Garmin: `test/support/fake_garmin.rb` runs a local stand-in. Never commit real responses
from your account; they are personal health data. Write fixtures by hand.

## Garmin API changes

`data/openapi.json` is fetched from Garmin's developer site and must not be edited by hand. To pick up a
new version:

```sh
bin/fetch-openapi           # download and extract the spec
bin/spec-diff               # summarize what changed
```

Then update `data/overrides.yml` until `bundle exec rake` passes, and regenerate the tool snapshot with
`UPDATE_SNAPSHOTS=1 bundle exec rake test`. If you use Claude Code, the `sync-garmin-openapi` skill
(`.claude/skills/`) does all of this. See [docs/overrides.md](docs/overrides.md) for the override format.

## Commits and pull requests

- PRs are squash-merged, and the **PR title must follow [Conventional Commits](https://www.conventionalcommits.org)**
  (checked in CI): `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`, `ci: ...`, `refactor: ...`, `test: ...`.
  Use `feat!:` or a `BREAKING CHANGE:` footer for breaking changes.
- [release-please](https://github.com/googleapis/release-please) turns merged titles into the changelog and
  version: `feat` bumps the minor version, `fix` the patch version (while below 1.0, breaking changes bump the
  minor version).
- Keep changes focused, add tests for behavior changes, and update docs when configuration changes.

## Releases

Maintainers merge the release PR that release-please keeps open. That creates the tag and GitHub release and
publishes `ghcr.io/cloetzi/garmin-connect-personal-api-mcp:<version>`, `:<major>.<minor>` and `:latest`.
Every push to `main` also publishes `:edge`.

By contributing you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md) and that your contributions are
licensed under the [Apache License 2.0](LICENSE).

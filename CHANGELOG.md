# Changelog

## 0.1.0 (2026-10-26)


### Features

* initial MCP server for the Garmin Connect Personal API ([0dbd4c7](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/0dbd4c7017e0780ab225a01469db4339a9d8b6cf))


### Bug Fixes

* bound binary tool results by the response size limit ([#10](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/10)) ([de07541](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/de07541192fd1fea59da235c557511332675af19))
* keep exception messages and request context out of unhandled exception logs ([#17](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/17)) ([8f56548](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/8f565487237e05feb03001a069b25454b750b01d))
* only send Garmin requests to Garmin or a loopback test server ([#16](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/16)) ([c433f6e](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/c433f6e66d4fe190b3cbef4058ed06e461140b2a))
* probe the configured listen address in the container health check ([#13](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/13)) ([1c481e5](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/1c481e528b336a102935e5e4203db4b080619cef))
* read the tools command's overrides file through Config ([#8](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/8)) ([92f8c8f](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/92f8c8fc6fad1b2c4df4ef5abfe5877b39bfe1c5))
* replay failed token exchanges faithfully and briefly for network errors ([#15](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/15)) ([afd6236](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/afd62364a9b40be16a30098ebecc5d51a58450dd))
* report every Garmin transport failure as a tool error ([#14](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/14)) ([70a0bd8](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/70a0bd86e71c53d87696890fd30023c205828cb7))
* stop re-exchanging the API key on every endpoint 401 ([#11](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/11)) ([fee719d](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/fee719dbd43fff1f6e67aba434dcd159dc5de6da))
* take the check-config transport as an argument ([#6](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/6)) ([7ddd5c3](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/7ddd5c3be9ee9150f83545b2272709b6c86092c1))
* validate every date range tool, inferring ranges from the spec ([#12](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/12)) ([35fafc6](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/35fafc6b6d7ee6dc150108436766efb694ee96bc))
* validate GARMIN_MCP_HOST and accept bracketed IPv6 addresses ([#18](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/18)) ([f26fc75](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/f26fc759a5a57e1832a966feb279cf93734de3e1))
* validate Origin when GARMIN_MCP_ALLOWED_HOSTS is * ([#9](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/9)) ([ad94ca8](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/ad94ca864e2db5c42a7088d0e86ecd925b7fbb2f))

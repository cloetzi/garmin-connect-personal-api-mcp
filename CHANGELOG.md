# Changelog

## [0.1.4](https://github.com/cloetzi/garmin-connect-personal-api-mcp/compare/v0.1.3...v0.1.4) (2026-11-21)


### Bug Fixes

* **deps:** update dependency ruby to v4.0.10 ([#39](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/39)) ([1e48817](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/1e48817c130dda18d63578cb06d3dfe32635f653))

## [0.1.3](https://github.com/cloetzi/garmin-connect-personal-api-mcp/compare/v0.1.2...v0.1.3) (2026-11-21)


### Bug Fixes

* **deps:** update dependency mcp to v1.11.0 ([#36](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/36)) ([5ec8813](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/5ec88135522d78eb68e65bbb07d0489534af460b))

## [0.1.2](https://github.com/cloetzi/garmin-connect-personal-api-mcp/compare/v0.1.1...v0.1.2) (2026-11-14)


### Bug Fixes

* **deps:** Bump mcp from 1.8.2 to 1.9.0 in the runtime group ([#24](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/24)) ([2551aa8](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/2551aa8b30da0cb9ed1cee19ece5f389fd777f94))
* **deps:** Bump rack from 3.2.7 to 3.2.8 ([#27](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/27)) ([1e7fcc0](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/1e7fcc0b89abeb23843d5e2169d0e8144eae9c08))
* **deps:** Bump ruby from `f1e5307` to `8ad6909` ([#25](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/25)) ([17df270](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/17df27064d453571b43488f344178b49a80da555))

## [0.1.1](https://github.com/cloetzi/garmin-connect-personal-api-mcp/compare/v0.1.0...v0.1.1) (2026-11-09)


### Bug Fixes

* **deps:** Bump mcp from 1.8.1 to 1.8.2 in the runtime group ([#19](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/19)) ([272a4d1](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/272a4d16e3beaf7916ba913cb7a5364130147888))
* **deps:** Bump ruby from `d0c5bef` to `f1e5307` ([#20](https://github.com/cloetzi/garmin-connect-personal-api-mcp/issues/20)) ([a71714d](https://github.com/cloetzi/garmin-connect-personal-api-mcp/commit/a71714d58935179a4e061e272f71b0b3afeb6e71))

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

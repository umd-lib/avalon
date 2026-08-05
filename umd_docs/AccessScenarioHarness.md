# Access Scenario Harness

UMD's permission model has several dimensions that interact — publication status, Item
Discovery (hiding), Item Access (visibility), collection inheritance, "Assign special
access", access tokens, IP Manager groups, and Course Reserves. Checking a change by hand
means editing settings through the UI once per combination, which is slow enough that
combinations get skipped.

This harness provisions every combination in one command, tells you what each persona
should see, and removes it all again.

## What it is made of

| Piece | Purpose |
|---|---|
| `app/services/umd_access_scenarios.rb` | The scenarios and their expected outcomes. Single source of truth. |
| `app/services/umd_access_scenarios/provisioner.rb` | Creates, updates and destroys the fixtures |
| `app/services/umd_access_scenarios/reporter.rb` | Markdown table, Cypress manifest, blackbox targets |
| `lib/tasks/umd_access_scenarios.rake` | `provision`, `report`, `teardown` |
| `spec/services/umd_access_scenarios_spec.rb` | Checks every declared expectation against real `Ability`/`SearchBuilder` behavior |
| `spec/cypress/integration/umd_access_scenarios_spec.js` | Drives the scenarios over HTTP |

## Running it

```bash
# Local development
docker-compose exec avalon bash -c "rails umd:access_scenarios:provision"
docker-compose exec avalon bash -c "rails umd:access_scenarios:report"

# Clean up (canaries survive -- see below)
docker-compose exec avalon bash -c "rails umd:access_scenarios:teardown"
docker-compose exec avalon bash -c "rails umd:access_scenarios:teardown INCLUDE_CANARIES=true"
```

### Media

Items come with a playable section by default, built from fixtures the rest of the suite
already uses — `spec/fixtures/videoshort.mp4` as the master file and its `.high`,
`.medium` and `.low` renditions as derivatives. They are attached directly, so nothing is
transcoded and provisioning stays fast. Nothing needs to be supplied to get a player on
the page.

Two ways to change that:

```bash
# Metadata only: faster, and enough for every discoverability and page-access check,
# but there is no player to look at.
METADATA_ONLY=true rails umd:access_scenarios:provision

# Your own files instead of the fixtures. DERIVATIVE_HLS_URL is only needed if you want
# the derivative to actually stream; without it the derivative points at the file.
MASTER_FILE_PATH=/path/to/video.mp4 \
  DERIVATIVE_PATH=/path/to/derivative.mp4 \
  DERIVATIVE_HLS_URL=http://av-local:3000/streams/... \
  rails umd:access_scenarios:provision
```

Note that all the `videoshort*` fixtures are byte-identical copies — the `.high` /
`.medium` / `.low` names describe the roles the harness assigns them, not different
encodings.

On av-test, provisioning writes real content into a shared environment, so it refuses to
run unless asked explicitly:

```bash
ALLOW_ACCESS_SCENARIOS=true HOST=https://av-test.lib.umd.edu \
  rails umd:access_scenarios:provision
```

### Configuration

| Env var | Purpose |
|---|---|
| `MASTER_FILE_PATH`, `DERIVATIVE_PATH`, `DERIVATIVE_HLS_URL` | Use your own media instead of the `videoshort` fixtures |
| `METADATA_ONLY` | Skip media entirely — no section, no player |
| `IP_GROUP_KEY`, `IP_IN_RANGE_ADDRESS`, `IP_OUT_OF_RANGE_ADDRESS` | IP Manager scenarios. Omitted, they are skipped rather than failed. |
| `SPECIAL_ACCESS_USER` | Username granted "Assign special access". Defaults to a local harness account; pass a real CAS username on av-test. |
| `HARNESS_MANAGER_USER` | Manager of the harness collections |
| `HOST` | Base URL used in the report and manifest |
| `ALLOW_ACCESS_SCENARIOS` | Required outside development/test |
| `INCLUDE_CANARIES` | Let teardown remove the canary items too |

## What gets created, and how teardown stays safe

Everything is tagged: a unit named `ZZ Access Scenarios (harness)`, collections named
`ZZ-AXS-<slug>`, items titled `ZZ-AXS <slug>` carrying an `other_identifier` of
`zz-axs-<slug>`. Teardown only ever touches collections whose name starts with `ZZ-AXS`,
so it cannot reach real content.

Two deliberate exceptions:

* **Course Reserves scenarios reuse the existing Streaming Reserves unit.** The harness
  never creates a second one, because `Ability.course_reserves_collection` assumes there is
  exactly one. Where that unit does not exist, those scenarios are skipped with a warning.
* **Canary items survive teardown**, because external monitoring probes them continuously.

Provisioning is idempotent — re-running after a definition changes updates the existing
items rather than creating duplicates.

## Reading the report

```
| Scenario | URL | anonymous | user | manager |
| item-restricted-hidden | https://…/media_objects/vt150j246 | 401, browse:hidden, no stream | 200, browse:hidden, stream | |
```

`200` means the item page renders; `401` means the "Restricted Content" page.
`browse:` is whether the item appears in search results. `stream` / `no stream` is whether
playback is permitted. A blank cell is not asserted for that persona — expectations are
deliberately sparse, declared only where the outcome is interesting.

The report also writes `spec/cypress/fixtures/access_scenarios.json`, which the Cypress
spec reads. Both that file and the blackbox target file are generated per environment and
are git-ignored: the manifest contains live access tokens.

## Automated checking

**The rspec check is the authoritative one.** It provisions each scenario and compares
every declared expectation against what `Ability` and `SearchBuilder` actually decide:

```bash
docker-compose exec test bash -c "bundle exec rspec spec/services/umd_access_scenarios_spec.rb"
```

A wrong entry in the table fails here rather than misleading whoever reads the report.

**Cypress** covers what only a real request shows — the 401 page, search results, and the
player rendering:

```bash
CYPRESS_grepTags=@access-scenarios docker-compose up cypress
```

Personas: anonymous, `cy.login()` accounts, access-token URLs from the manifest, and IP
personas via an `X-Forwarded-For` header. That header only becomes `request.ip` in local
Docker, where Rails treats the private-range source as a trusted proxy — behind av-test's
ingress it is overwritten, which is why IP behavior there is checked by probing from a
different network instead.

## Canaries and blackbox probes

A few scenarios are marked `canary: true`. Provisioned once on av-test and never torn down,
they give external monitoring something stable to watch — and probing from two network
locations is the only way to exercise the real UMD IP Manager path, since it uses real
source addresses rather than a header.

```bash
FORMAT=blackbox HOST=https://av-test.lib.umd.edu rails umd:access_scenarios:report
```

writes `umd_docs/monitoring/blackbox_targets.yml`, a Prometheus `file_sd` list carrying the
expected status for each canary as a label. Point two `blackbox_exporter` instances at it,
one on-campus/VPN and one outside, and label the vantage in the Prometheus scrape config —
the IP-dependent rows are *expected* to differ between them.

Pair it with three modules: expect 200, expect 401, and a body check
(`fail_if_body_matches_regexp: Restricted Content`) — a 200 that renders the restricted page
would otherwise pass. Alert on `probe_success == 0` or a status that no longer matches its
`expected_status_*` label.

Limits: no session, so logged-in personas stay with Cypress; no JS, so player rendering is
not covered (the IIIF manifest URL is a plain GET and *is* probeable). The token canary
needs a long-expiry token, held as a Prometheus secret rather than committed, and a renewal
reminder.

## Adding a scenario

Add an entry to `SCENARIOS` in `app/services/umd_access_scenarios.rb` with the collection
and item settings and the outcomes you expect, then run the rspec check. If it fails,
either your expectation is wrong or the behavior is — decide which before changing either.
That is the whole point of the file.

Note that expectations record *actual* behavior, including behavior that is arguably wrong:
`item-unpublished-public` pins the fact that an unpublished item with public Item Access
still renders its page, a known divergence tracked as LIBAVALON-178. Pinning it means the
day it changes, it changes deliberately.

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
| `PROBE_NAMESPACE` | Kubernetes namespace the generated Probes declare (default `test`) |
| `PROBE_ENVIRONMENT` | Prefix for the probe `jobName` (defaults to the namespace) |
| `PROBE_RUNBOOK` | URL for the optional `runbook` label — see [Runbook label](#runbook-label). Leave unset until a runbook exists. |

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
FORMAT=probes HOST=https://av-test.lib.umd.edu PROBE_NAMESPACE=test \
  rails umd:access_scenarios:report
```

writes `umd_docs/monitoring/access_scenario_probes.yaml` — `Probe` CRDs
(`monitoring.coreos.com/v1`) for the DevOps `blackbox_exporter`. Copy them into the Avalon
stack repository so the checks deploy with the stack; they are git-ignored here because
they are generated per environment.

The vantage point is not something we configure — a **module** encodes both the expected
status and the network the request comes from, and the exporter reaches non-`internal`
networks through a forward proxy. One Probe carries one module, so the generator groups the
canaries by module:

| Module | What it asserts |
| --- | --- |
| `http_2xx_internet` | Hidden-but-public items, and the access token URL, are viewable from off campus |
| `http_401_internet` | Hidden restricted and staff-only items are refused off campus |
| `http_2xx_campus` | IP-Manager-granted items are viewable from campus (needs IP canaries provisioned) |

Failures are told apart by the `instance` label, which carries the URL. Alert on
`probe_success == 0`; the module already encodes what "success" means, so no
expected-status label is needed.

### Modules to request from DevOps

Avalon answers restricted content with **401**, and the exporter defines only `2xx` and
`403` modules — an `http_403_*` probe reports a *failure* for a correct 401. The generated
file names the missing modules in its header and the rake task prints them, so the manifest
doubles as the request. Until they exist, only the `http_2xx_internet` Probe can be
deployed.

The DevOps team is willing to add modules, so the ask is concrete. Each is an ordinary
`http` prober differing only in `valid_status_codes` and which forward proxy it egresses
through — the same shape as the existing `http_403_*` modules:

```yaml
http_401_internet:
  prober: http
  timeout: 10s
  http:
    valid_status_codes: [401]
    proxy_url: <the internet/AWS egress proxy the http_2xx_internet module uses>

http_401_campus:      # needed once the IP-Manager canaries are provisioned
  prober: http
  timeout: 10s
  http:
    valid_status_codes: [401]
    proxy_url: <the campus egress proxy>
```

`http_2xx_campus` is already on their planned list and needs no new definition, just
enabling. No body-matching module is needed: a hidden public item that regressed would
answer 401 rather than a 200 carrying the "Restricted Content" page, so the status code is
decisive on its own.

### Runbook label

`PROBE_RUNBOOK` sets the optional `runbook` label, which AlertManager surfaces as
`runbook_url` in the alert itself. It is worth setting for these probes in particular,
because a failing access-control canary means the permission model changed — not something
an on-call operator can act on from a job name alone.

The runbook is [monitoring/runbooks/access-control.md](monitoring/runbooks/access-control.md):

```bash
PROBE_RUNBOOK=https://github.com/umd-lib/avalon/blob/avalon-main/umd_docs/monitoring/runbooks/access-control.md
```

It lives here rather than in the stack repository (where the DevOps docs suggest putting
runbooks) because every remediation step is a rake task in this repository and the behavior
it explains is defined by `app/models/ability.rb` — keeping them together is what stops the
runbook going stale. Move it if the stack repository turns out to be the better home; only
the label's URL needs to change.

The `campus` Probe is only generated when the IP scenarios were provisioned
(`IP_GROUP_KEY` and `IP_IN_RANGE_ADDRESS` set) — that is the one behavior the harness
cannot fake over HTTP, and the reason probing from a second network matters.

Limits: no session, so logged-in personas stay with Cypress; no JS, so player rendering is
not covered (the IIIF manifest URL is a plain GET and *is* probeable). The token canary
embeds a live token in the manifest, which is why the file is not committed here — it needs
a renewal reminder before its year is up.

## Adding a scenario

Add an entry to `SCENARIOS` in `app/services/umd_access_scenarios.rb` with the collection
and item settings and the outcomes you expect, then run the rspec check. If it fails,
either your expectation is wrong or the behavior is — decide which before changing either.
That is the whole point of the file.

Note that expectations record *actual* behavior, including behavior that is arguably wrong:
`item-unpublished-public` pins the fact that an unpublished item with public Item Access
still renders its page, a known divergence tracked as LIBAVALON-178. Pinning it means the
day it changes, it changes deliberately.

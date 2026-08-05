# Runbook: Avalon access control canary failed

An access control canary stopped answering the way it should. These probes watch a handful
of permanently-provisioned items on av-test whose access settings never change, so a
failure means either the items were disturbed or **the permission model behaves differently
than it did yesterday**.

Background: [AccessScenarioHarness.md](../../AccessScenarioHarness.md) (what the canaries
are), [AvalonPermissions.md](../../AvalonPermissions.md) (what the rules are meant to be).

## Which alert fired

| Job | Asserts | Failing means |
|---|---|---|
| `*-avalon-access-http-2xx-internet` | Hidden-but-public items, and an access token URL, are viewable from off campus | Something that should be publicly reachable is not |
| `*-avalon-access-http-401-internet` | Hidden restricted and staff-only items are refused from off campus | **Restricted content may be exposed** |
| `*-avalon-access-http-2xx-campus` | IP-Manager-granted items are viewable from campus | Campus/VPN-based access is broken |

The failing URL is in the alert's `instance` label.

## How urgent

* **`http_401_internet` failing is the urgent one.** The probe expects a refusal and did not
  get one, so content that should be restricted may be readable by anyone. Treat as a
  potential exposure: confirm, then escalate immediately.
* `http_2xx_*` failing means over-restriction — real, user-visible breakage, but nothing is
  leaking. Normal priority.

## First five minutes

Confirm the probe rather than trusting it, from off campus (not on VPN):

```bash
curl -s -o /dev/null -w '%{http_code}\n' <the instance URL>
```

* Matches the expectation → transient; check whether the probe has recovered.
* Differs → real. Continue below.

Then check the item still exists and still has the settings it should:

```bash
# on av-test
ALLOW_ACCESS_SCENARIOS=true rails umd:access_scenarios:report
```

The table prints every canary with the result expected of each persona. Compare it against
what you just saw.

## Common causes, most likely first

**1. The canary item was deleted or torn down.**
`umd:access_scenarios:teardown` leaves canaries alone unless run with
`INCLUDE_CANARIES=true`. Someone may have run it that way, or deleted the item through the
UI. A deleted item answers 404, not 401/200, so the probe fails either way.

Fix: re-provision, which recreates it with the correct settings.

```bash
ALLOW_ACCESS_SCENARIOS=true rails umd:access_scenarios:provision
```

**Item ids change when items are recreated**, so regenerate and redeploy the Probe
manifests afterwards (see step 5 below).

**2. The access token expired.**
Only affects the `token-stream` canary in the 2xx group. Tokens are minted with a one-year
expiry; an expired one answers 401 where the probe expects 200.

Fix: re-provision (mints a fresh token), then regenerate and redeploy the Probes — the
token URL changes.

**3. Someone edited the canary's access settings in the UI.**
The harness collections and items are named `ZZ-AXS-*`; they are not real content and
should not be edited. Re-provisioning is idempotent and resets them to their declared
settings.

**4. A collection changed but Solr was not reindexed.**
Collection-level discoverability lives in the `inheritable_discover_access_group_ssim` Solr
field, written only when a collection is saved or reindexed. A collection restored from a
backup, or migrated, can be stale. Symptom: browse/search behavior disagrees with the item
page.

Fix: re-save or reindex the collection.

**5. The permission model actually changed.**
Nothing above applies and the settings are correct — a deploy changed behavior. This is
what the canaries exist to catch.

Check what shipped recently, then run the authoritative check locally:

```bash
docker-compose exec test bash -c "bundle exec rspec spec/services/umd_access_scenarios_spec.rb"
```

That compares every declared expectation against what `Ability` and `SearchBuilder` decide.
If it fails locally, the regression is reproducible and belongs in a ticket referencing
LIBAVALON-554. If it passes locally but av-test disagrees, suspect environment: Solr index
state, settings overrides, or a partial deploy.

## After fixing

If items were recreated, the URLs in the deployed Probes are stale:

```bash
FORMAT=probes HOST=https://av-test.lib.umd.edu PROBE_NAMESPACE=test \
  rails umd:access_scenarios:report
```

Copy the regenerated manifest into the Avalon stack repository and deploy. Until then the
probes are checking items that no longer exist.

## Escalation

Anything in cause 5, and any confirmed `http_401_internet` failure, goes to the Avalon
developers — a real permission regression affects every restricted item in the repository,
not just the canary that caught it.

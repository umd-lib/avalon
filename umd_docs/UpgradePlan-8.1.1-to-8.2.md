# Avalon Upgrade Plan: 8.1.1 → 8.2

## Overview

This document describes the plan for upgrading UMD's Avalon fork from **v8.1.1 (tag
`8.1.1-umd-0`)** to **upstream v8.2**, preserving all UMD customizations.

**Strategy:** Single merge of `upstream/v8.2` on top of the completed 8.1.1 UMD branch.

Upstream release notes: <https://github.com/avalonmediasystem/avalon/releases/tag/v8.2>

Upgrade guide: <https://samvera.atlassian.net/wiki/spaces/AVALON/pages/4054089759/Upgrading+Avalon+8.1+to+Avalon+8.2>

---

## Key Changes in v8.2

### Major Features

1. **Units as First-Class Objects** — Units are now full Fedora-backed objects (`Admin::Unit`
   with roles, admins, default access, and permission inheritance). A new `unit_admin` role
   replaces the concept of "manager-creates-collection". A post-upgrade rake task
   (`avalon:migration:admin_units`) creates `Admin::Unit` objects from the existing
   controlled vocabulary.

2. **API Token Encryption** — `ApiToken#token` is now encrypted at rest using Active Record
   Encryption. Three new env vars are required (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
   `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`)
   and existing tokens must be migrated via a one-time runner.

3. **jsbundling-rails replaces Shakapacker** — The JS build pipeline migrates from
   `shakapacker` (Webpack 5 via `@rails/webpacker`) to `jsbundling-rails` + `cssbundling-rails`
   with a standalone `webpack.config.js`. The old `app/javascript/packs/` entry points
   (`application.js`, `server-bundle.js`) are replaced by a single `app/javascript/application.js`.

4. **Ramp 5.1** — Upgrades from `@samvera/ramp@^4.0.2` to `^5.1.0`. React 19 is now
   required by Ramp. VideoJS is bundled inside Ramp and no longer a peer dependency.
   Key new features: Audio Description support, forced captions, playback position persistence.

5. **Accessibility Compliance Enforcement** — Optional feature to block publication of
   items lacking captions/transcripts after a configurable date. Disabled by default.

6. **Saved Searches Disabled** — Blacklight's DB-backed search persistence is disabled.
   Existing `searches` table rows should be truncated post-deploy.

7. **jQuery Dependencies Removed** — `select2`, `datatables` (jquery-datatables), jQuery
   fileupload plugin, and `nestable`/`nestedSortable` have been replaced with vanilla JS
   equivalents (`sortablejs`, `tom-select`).

8. **AWS Elastic Transcoder removed** — `aws-sdk-elastictranscoder` and `aws-sdk-ses`
   replaced by `aws-sdk-mediaconvert`, `aws-sdk-cloudwatchevents`,
   `aws-sdk-cloudwatchlogs`, and `aws-actionmailer-ses`.

---

## Dependency Matrix

| Component | v8.1.1 | v8.2 |
|-----------|--------|------|
| **Ruby** | 3.4 | **4.x** (4-bookworm Docker image) |
| **Node.js** | 20 | **24** |
| **Rails** | ~> 8.0 | ~> 8.0, >= 8.0.4.1 |
| **Ramp** | ^4.0.2 | **^5.1.0** |
| **active-fedora** | git ref | **~> 16.0** (stable release) |
| **active_encode** | ~> 1.3.0 | **~> 2.0** |
| **speedy-af** | ~> 0.5.0 | **~> 0.6** |
| **sprockets** | ~> 3.7.2 | >= 4 |
| **JS bundler** | shakapacker / webpack | **jsbundling-rails / webpack** |
| **CSS bundler** | sassc-rails / sprockets | **cssbundling-rails / sass CLI** |
| **avalon-about** | tag `avalon-r8.0` | branch `main` |
| **about_page** | tag `avalon-r6.5` | branch `main` |

---

## Breaking Changes Summary

| Area | Change | Risk |
|------|--------|------|
| **Ruby 4** | 3.4 → 4.x (Docker base image) | Medium |
| **Node.js 24** | 20 → 24 | Low |
| **Units as objects** | `Admin::Unit` now Fedora-backed; `group_manager` system group removed | **High** |
| **API token encryption** | Requires 3 new env vars; existing tokens need one-time migration | **High** |
| **jsbundling-rails** | Replaces shakapacker; packs/ entry points deleted; new `application.js` | **High** |
| **Ramp 5.1 / React 19** | Breaking API changes from Ramp 4 to Ramp 5 | **High** |
| **AWS Transcoder removed** | `aws-sdk-elastictranscoder` → `aws-sdk-mediaconvert` | Medium |
| **`coffee-rails` removed** | All CoffeeScript → plain JS (completed upstream) | Low |
| **`font-awesome-rails` removed** | Replaced by `@fortawesome/fontawesome-free` npm package | Medium |
| **`shakapacker` removed** | Build pipeline changed; `config/webpack/` restructured | **High** |
| **`bootstrap-toggle-rails` removed** | HTML toggle pattern may have changed | Medium |
| **`google-analytics-rails` stays** | UMD uses Matomo, not GA — verify no conflict | Low |
| **Saved searches disabled** | `searches` DB table should be truncated post-deploy | Low |
| **`derivative.use_presigned_url`** | New default `true` — verify S3 streaming behavior | Medium |
| **`system_groups` change** | `manager` and `group_manager` removed from default list | **High** |

---

## UMD Customizations Inventory

All customizations below must be preserved through the upgrade.

### UMD-Only Gems (must survive merge)

| Gem | Group | Purpose |
|-----|-------|---------|
| `omniauth-rails_csrf_protection` | default | CSRF protection for OmniAuth (SAML) |
| `sidekiq-limit_fetch` | default | Sidekiq queue concurrency limits |
| `health_check` | default | `/health_check` endpoint (K8s liveness probe) |
| `rbtrace ~> 0.5.3` | production | Ruby process tracing |

### UMD Code Customizations

| Feature | Primary Files | Jira |
|---------|--------------|------|
| SAML/CAS Authentication | `config/settings.yml`, `config/initializers/devise.rb` | — |
| Access Tokens (JWT) | `app/models/access_token.rb`, `app/controllers/access_tokens_controller.rb`, `config/routes.rb` | LIBAVALON-198 |
| UMD IP Manager Integration | `app/services/umd_ip_manager.rb`, `app/models/ability.rb` | — |
| Master File Downloads | `app/controllers/master_files_controller.rb`, `app/models/master_file.rb` | LIBAVALON-398 |
| Restricted Playback / Jim Henson msg | `app/javascript/components/UmdRestrictedPlayback.jsx`, `app/models/ability.rb` | LIBAVALON-403 |
| Aeon "Request from Special Collections" | `app/views/media_objects/_item_view.html.erb` | LIBAVALON-93 |
| UMD Handle Integration | `app/services/umd_handle.rb`, `app/controllers/media_objects_controller.rb` | — |
| Course Reserves / Course Name Facet | `app/controllers/catalog_controller.rb`, `app/models/course.rb`, `app/views/collections/course_reserves.html.erb` | LIBAVALON-438 |
| Matomo Analytics | `app/views/modules/_matomo_analytics.html.erb`, `app/views/layouts/avalon.html.erb` | — |
| Docker jemalloc / YJIT / Puma tuning | `Dockerfile` | — |
| S3 Archive / Master File Management | `app/jobs/migrate_to_s3_job.rb`, `lib/tasks/migrate_to_s3.rake` | — |
| UMD IP Manager Leases | `app/models/lease.rb`, `app/models/access_control_step.rb` | — |
| Streaming Reserves | `app/models/media_object.rb` (`is_streaming_reserve?`) | LIBAVALON-168 |
| UMD Facet Filter (React) | `app/javascript/components/UMDFacetFilter.jsx`, `app/javascript/facet_filter_react_mount.js` | — |

---

## Pre-Merge Checklist

### Pre-Upgrade Verification

```bash
# Confirm unit migration rake task is available (will be needed post-deploy)
bundle exec rake --tasks | grep admin_units

# Confirm no ApiToken records have nil tokens (pre-encryption state)
bundle exec rails runner "puts ApiToken.where(token: nil).count"
# Expected: 0

# Confirm active_encode ~> 2.0 doesn't break existing encode records
# Check ActiveEncode::EncodeRecord table column types (raw_object should be medium text)
bundle exec rails runner "puts ActiveRecord::Base.connection.columns('active_encode_encode_records').map {|c| [c.name, c.sql_type]}.to_h"
```

### Gem Compatibility Pre-Check

Before merging, verify Ruby 4 and Rails 8.0.4.1+ compatibility:

- `sidekiq-limit_fetch`: <https://github.com/brainopia/sidekiq-limit_fetch>
- `health_check`: <https://github.com/ianheggie/health_check>
- `rbtrace`: <https://github.com/tmm1/rbtrace>
- `omniauth-rails_csrf_protection`: <https://github.com/cookpad/omniauth-rails_csrf_protection>

---

## Phase 1 — Merge v8.2

```bash
git checkout release/8.2.0-umd-0   # or create from 8.1.1-umd-0
git merge upstream/v8.2 --no-ff -m "Merge upstream Avalon v8.2 into release/8.2.0-umd-0"
# Resolve conflicts — see guidance below
git add -A && git commit
```

### 1.1 Dockerfile — Ruby 4 + Node 24

```dockerfile
# Update ALL base image references:
#   ruby:3.4-bookworm        → ruby:4-bookworm
#   ruby:3.4-slim-bookworm   → ruby:4-slim-bookworm
#   node:20-bookworm-slim    → node:24-bookworm-slim

# Update Node.js apt source:
#   node_20.x → node_24.x

# ENV syntax fix (= required in modern Docker):
#   ENV FOO bar  →  ENV FOO=bar

# Remove from production stage (now set in bundle stage):
#   LD_PRELOAD, RUBY_YJIT_ENABLE, MALLOC_CONF
# Keep UMD Puma tuning:
# UMD Customization
ENV PUMA_WORKERS=4
ENV RAILS_MAX_THREADS=5
# End UMD Customization

# Add NODE_ENV=production to assets and prod stages (new in v8.2):
ENV NODE_ENV=production
```

Also remove `.ruby-version` file if present (project moved to Docker-only Ruby).

### 1.2 Gemfile — v8.2 Changes

**Remove (dropped in v8.2):**
```ruby
gem 'coffee-rails', '~> 5.0'
gem 'font-awesome-rails'
gem 'jquery-datatables'
gem 'terser'
gem 'shakapacker'
gem 'bootstrap-toggle-rails'
```

**Update version constraints:**
```ruby
gem 'rails', '~>8.0', '>= 8.0.4.1'
gem 'sprockets', '>= 4'
gem 'resolv-replace', '>= 0.2.0'
gem 'active-fedora', '~> 16.0'      # was: git ref
gem 'active_encode', '~> 2.0'       # was: ~> 1.3.0
gem 'speedy-af', '~> 0.6'           # was: ~> 0.5.0
gem 'avalon-about', git: 'https://github.com/avalonmediasystem/avalon-about.git', branch: 'main'
gem 'about_page', git: 'https://github.com/avalonmediasystem/about_page.git', branch: 'main'

# New gems:
gem 'net-imap', '>= 0.6.2'
gem "cssbundling-rails", "~> 1.4"
gem 'jsbundling-rails', '~> 1.3'
gem 'faraday-retry'
```

**AWS group updates:**
```ruby
group :aws, optional: true do
  gem 'aws-actionmailer-ses'           # new (replaces aws-sdk-ses)
  gem 'aws-sdk-cloudwatchevents'       # new
  gem 'aws-sdk-cloudwatchlogs'         # new
  gem 'aws-sdk-mediaconvert', ">= 1.157.0"  # new (replaces aws-sdk-elastictranscoder)
  # remove: gem 'aws-sdk-elastictranscoder'
  # remove: gem 'aws-sdk-ses'
end
```

**Restore UMD-only gems** (verify they survive the merge):
```ruby
# UMD Customization
gem "omniauth-rails_csrf_protection"
# End UMD Customization
# ...
# UMD Customization
gem 'sidekiq-limit_fetch'
# End UMD Customization
# ...
# UMD Customization
gem 'health_check'
# End UMD Customization

group :production do
  # UMD Customization
  gem 'rbtrace', '~> 0.5.3'
  # End UMD Customization
end
```

After editing:
```bash
bundle install
git add Gemfile Gemfile.lock
git commit -m "UMD: Update Gemfile for Avalon 8.2 / Ruby 4 compatibility"
```

### 1.3 jsbundling-rails Migration

v8.2 replaces `shakapacker` with `jsbundling-rails`. The old `app/javascript/packs/`
directory is replaced by a single `app/javascript/application.js` entry point.

**Key structural change:**
- **Old (shakapacker):** `app/javascript/packs/application.js` + `app/javascript/packs/server-bundle.js`
- **New (jsbundling):** `app/javascript/application.js` (single entry point)

**Verify all UMD components are registered in the new `app/javascript/application.js`:**

```js
// UMD Customization
import "./facet_filter_react_mount";
// End UMD Customization
// ...
// UMD Customization
import UMDFacetFilter from './components/UMDFacetFilter';
// End UMD Customization
// ...
ReactOnRails.register({
  // ...
  // UMD Customization
  UMDFacetFilter,
  // End UMD Customization
});
```

> **Note:** `UmdMasterFiles`, `UmdRestrictedPlayback`, `UmdCopyHandleUrlButton`, and
> `UmdMetadataDisplay` are used as sub-components inside `MediaObjectRamp`, not as
> top-level `react_component` calls. They do NOT need to be registered in
> `ReactOnRails.register()` — only `MediaObjectRamp` does.
> Verify by running: `grep -r "react_component" app/views/ --include="*.erb" | grep -iE "umd|Umd"`

**CSS bundling change:**
```bash
# New build commands (replacing SCSS via Sprockets):
yarn build:css       # production
yarn build:css:dev   # dev with source maps and watch
```

The `application.sass.scss` is now the root stylesheet compiled by the Sass CLI.
Verify UMD-specific CSS imports are included in that file.

### 1.4 Ramp 5.1 Migration

Review [Ramp 5.1.0 release notes](https://github.com/samvera-labs/ramp/releases/tag/v5.1.0)
before modifying `app/javascript/components/MediaObjectRamp.jsx`.

**Breaking changes from Ramp 4 to Ramp 5:**
- React 19 is now required
- VideoJS is bundled inside Ramp (no longer a peer dependency)
- Build system migrated to Vite
- New Audio Description track support (`umd_access_control` props may need updating)
- `EmbeddedRamp` component also updated

Re-verify all UMD prop integrations in `MediaObjectRamp.jsx`:

```bash
grep -n "UMD\|umd_" app/javascript/components/MediaObjectRamp.jsx | head -30
```

Key UMD integration points to verify:
- `UmdRestrictedPlayback` render at `umd_access_control.jim_hension_collection`
- `UmdCopyHandleUrlButton` at `umd_metadata.handleUrl`
- `UmdMetadataDisplay` at `umd_metadata.handleUrl`
- `UmdMasterFiles` at `master_file_downloads`

### 1.5 Units Permission Model Changes

v8.2 significantly restructures user permissions:

- `group_manager` system group is **removed**
- `manager` is **removed** from `system_groups` (only `administrator` remains)
- New `unit_admin` role introduced
- Permissions now inherit: Unit → Collection → Item
- `can :create, Admin::Collection` now requires `is_unit_admin_of_any_unit?` (was `is_manager?`)
- `can :create, MediaObject` now also checks `is_member_of_any_unit?`

**UMD impact on `ability.rb`:**

Review these UMD blocks for compatibility with the new permission hierarchy:

1. **Streaming reserves** (`LIBAVALON-168`) — `is_streaming_reserve?` logic still uses
   `collection.unit` string. Verify the string comparison still works when units become
   Fedora objects.

2. **IP Manager groups** — The `@user_groups` augmentation via `UmdIpManager` still applies.
   Verify it works with the new `is_member_of_any_unit?` checks.

3. **`master_file_download` permission** — Check that the custom ability block survives
   the permission hierarchy changes.

4. **Access Tokens** — JWT streaming/download grants are outside the CanCan flow; verify
   they still bypass the new unit-based checks correctly.

```bash
# After merge, audit ability changes:
git diff v8.1.1..HEAD -- app/models/ability.rb
bundle exec rspec spec/models/ability_spec.rb
```

### 1.6 API Token Encryption (Critical Post-Deploy Step)

ActiveRecord Encryption is new in v8.2 (`ApiToken` now uses `encrypts :token,
deterministic: true`). This requires:

**Environment variables (add to K8s configmap/secrets):**
```bash
# Generate with:
RAILS_ENV=production bundle exec rails db:encryption:init
# Copy the output into:
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

**Temporary migration flag** (for zero-downtime token migration):
```yaml
# config/settings.yml (optional - enables reading unencrypted tokens during migration)
# ACTIVE_RECORD_ENCRYPTION_MIGRATION=true
```

**Post-deploy one-time migration:**
```bash
# Migrate existing API tokens to encrypted storage:
RAILS_ENV=production ACTIVE_RECORD_ENCRYPTION_MIGRATION=true \
  bundle exec rails r 'ApiToken.all.each(&:encrypt)'
```

> **UMD note:** UMD uses its own `AccessToken` model (JWT-based), not `ApiToken`. However,
> `ApiToken` is used for the Avalon API authentication (Hydra). Both must work correctly.

### 1.7 Unit Migration (Required Post-Deploy)

After deploying v8.2, run the unit migration rake task to create `Admin::Unit` Fedora
objects from the existing controlled vocabulary:

```bash
# Docker:
docker-compose exec avalon /bin/bash -c \
  "RAILS_ENV=production bundle exec rake avalon:migration:admin_units unit_admin_username=admin@example.umd.edu"

# K8s:
kubectl exec -it avalon-0 -c avalon -- bash -c \
  "bundle exec rake avalon:migration:admin_units unit_admin_username=admin@umd.edu"
```

> **UMD note:** This migration creates unit objects for ALL existing units in the
> controlled vocabulary, including `Streaming Reserves`. After running, manually assign
> appropriate unit admins to each unit.

### 1.8 Config Changes

**`config/settings.yml` — new/changed settings:**

```yaml
# Changed default in v8.2 (manager and group_manager removed):
groups:
  system_groups: [administrator]

# New default in v8.2:
derivative:
  use_presigned_url: true  # Uses S3 presigned URLs for derivative downloads

# New optional settings:
search_pagination:
  theme: 'blacklight'
  window: 2
  left: 2
  right: 0

accessibility_compliance:
  enforce: false
  compliance_date: '2026-04-24'
```

**K8s `base/configs/settings.yml`:** Review whether `derivative.use_presigned_url: true`
is compatible with UMD's S3 streaming setup. If CloudFront signing is in use, presigned
S3 URLs may conflict with signed CloudFront URLs — test in the test environment first.

### 1.9 Saved Searches Cleanup

After deployment, optionally truncate the now-unused `searches` table:

```bash
RAILS_ENV=production bundle exec rails r \
  'ActiveRecord::Base.connection.truncate(Search.table_name)'
```

### 1.10 Font Awesome Migration

`font-awesome-rails` gem is removed; Font Awesome is now served via the
`@fortawesome/fontawesome-free` npm package. If UMD views use Font Awesome icons via
the old Sprockets helpers (`fa_icon`, `fa-icon`), replace them with standard HTML
`<i class="fa-solid fa-...">` tags.

```bash
# Audit font-awesome usage in UMD views:
grep -rn "fa_icon\|fa-icon\|font-awesome" app/views/ --include="*.erb" | grep -v "fontawesome-free"
```

---

## Phase 2 — Build & Tag

> **M-series Mac:** Build Docker images in the Kubernetes cluster, not locally.
> See <https://github.com/umd-lib/k8s/blob/main/docs/DockerBuilds.md>.

```bash
# RC build
docker build -t docker.lib.umd.edu/avalon:8.2.0-umd-0-rc1 .
docker push docker.lib.umd.edu/avalon:8.2.0-umd-0-rc1

# After test/QA sign-off
docker build -t docker.lib.umd.edu/avalon:8.2.0-umd-0 .
docker push docker.lib.umd.edu/avalon:8.2.0-umd-0

# Tag the Git release
git tag 8.2.0-umd-0
git push origin release/8.2.0-umd-0 --tags
```

---

## Phase 3 — K8s Deployment

### Pre-Deploy Checklist (app repo side)

- [ ] `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` added to K8s secret
- [ ] `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` added to K8s secret
- [ ] `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` added to K8s secret
- [ ] `derivative.use_presigned_url` decision documented (S3 vs CloudFront signing)
- [ ] Unit migration runbook prepared (with unit_admin_username)
- [ ] `group_manager` / `manager` system group removal impact reviewed
- [ ] `system_groups: [administrator]` change applied to K8s `base/configs/settings.yml`
- [ ] `accessibility_compliance` settings added to K8s `base/configs/settings.yml`
- [ ] `search_pagination` settings added (optional)
- [ ] Node 24 confirmed in Dockerfile and K8s base image

### Rollout Order

1. **test** — functional, unit permission model, and API token encryption testing (RC image)
2. **qa** — stakeholder acceptance testing
3. **sandbox** — if applicable
4. **prod** — production deployment (release image; run post-deploy steps below)

### Post-Deploy Steps (each environment)

```bash
# 1. Run DB migration
bundle exec rake db:migrate

# 2. Run unit migration (REQUIRED - creates Admin::Unit objects)
bundle exec rake avalon:migration:admin_units unit_admin_username=admin@umd.edu

# 3. Migrate API tokens to encrypted storage
ACTIVE_RECORD_ENCRYPTION_MIGRATION=true bundle exec rails r 'ApiToken.all.each(&:encrypt)'

# 4. (Optional) Clear saved searches
bundle exec rails r 'ActiveRecord::Base.connection.truncate(Search.table_name)'

# 5. Trigger Solr reindex
bundle exec rake avalon:reindex
```

---

## Testing Checklist

### Local Spec Suite

- [ ] `bundle exec rspec` — full suite passes
- [ ] `bundle exec rspec spec/models/ability_spec.rb` — UMD permission model intact
- [ ] `bundle exec rspec spec/controllers/access_tokens_controller_spec.rb`
- [ ] `bundle exec rspec spec/models/media_object_spec.rb` — Solr indexing intact

### UMD Feature Regression (K8s test environment)

**Authentication & Authorization:**
- [ ] SAML/CAS login works (Chrome; Firefox still broken with `av-local`)
- [ ] `AccessToken` JWT grants stream/download end-to-end
- [ ] UMD IP Manager groups apply correctly (`umd.ip.manager:` prefix)
- [ ] `is_streaming_reserve?` correctly identifies Streaming Reserves collection items
- [ ] `/health_check` returns `success` (K8s liveness probe)

**Permissions (v8.2 Unit Model):**
- [ ] Unit admins can create Collections within their unit
- [ ] Collection managers/editors retain their abilities
- [ ] Items inherit access from Collection (and Collection from Unit)
- [ ] `disable_inheritance` flag works on individual items
- [ ] Streaming Reserves unit behavior unchanged (`is_streaming_reserve?` still correct)

**API Token Encryption:**
- [ ] Existing API tokens work after migration (no auth failures)
- [ ] New API tokens created post-upgrade are encrypted at rest
- [ ] Encryption env vars are set in K8s secrets before deploying

**Media Playback & UMD Components:**
- [ ] `UmdRestrictedPlayback` VPN message appears for restricted items
- [ ] Jim Henson collection shows distinct message
- [ ] `UmdCopyHandleUrlButton` copies handle URL correctly
- [ ] `UmdMetadataDisplay` shows handle URL
- [ ] `UmdMasterFiles` Files tab visible to `master_file_download` users only
- [ ] Ramp 5.1 media player loads and plays HLS streams
- [ ] Ramp 5.1 Audio Description track support (if any UMD items have AD files)

**Course Reserves & Facets:**
- [ ] `course_title_ssim` Course Name facet appears in Blacklight search
- [ ] `UMDFacetFilter` case-insensitive substring filter works in the "More" facet dialog
- [ ] Blacklight pagination uses new `search_pagination` window settings

**Aeon & Handle:**
- [ ] "Request from Special Collections" Aeon button appears and pre-populates form
- [ ] Publishing triggers handle minting via `umd-handle` service

**Matomo Analytics:**
- [ ] Matomo script fires when env vars are set; absent when not set
- [ ] No interference from `font-awesome-rails` removal

**Asset Pipeline:**
- [ ] `yarn build:css` compiles without errors
- [ ] `yarn build` (jsbundling webpack) compiles without errors
- [ ] All Sprockets assets compile correctly
- [ ] No missing Font Awesome icons (post-`font-awesome-rails` removal)

**Admin Dashboard (new in v8.2):**
- [ ] `/admin/collections` redirects to `/admin/dashboard` (new dashboard)
- [ ] Units are visible and manageable in admin dashboard
- [ ] Collections are visible under their parent units

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Unit permission model breaks UMD `is_streaming_reserve?` | **High** | Verify `collection.unit` returns name string after unit migration; update if needed |
| API token encryption migration causes API auth failures | **High** | Run token migration immediately after deploy; test API endpoints before opening to users |
| jsbundling migration breaks UMD component rendering | **High** | Verify all `react_component` calls in views have corresponding imports in `application.js` |
| Ramp 5 API changes break `MediaObjectRamp.jsx` UMD integrations | **High** | Read Ramp 5 changelog; re-test all 4 UMD sub-component integration points |
| `derivative.use_presigned_url` conflicts with CloudFront signing | **Medium** | Test S3 derivative downloads in test env; revert to `false` if needed |
| `group_manager` system group removal locks out existing group managers | **Medium** | Audit existing `group_manager` group members; reassign roles as needed before deploy |
| `sidekiq-limit_fetch` / `health_check` Ruby 4 incompatibility | **Medium** | Check GitHub releases pre-merge; `/health_check` is critical for K8s liveness |
| Font Awesome icon breakage post `font-awesome-rails` removal | **Medium** | Run grep audit; update icon HTML in UMD views |
| `accessibility_compliance.enforce` enabled accidentally | **Low** | Default is `false` — confirm this is preserved in K8s config |
| Saved searches table bloat after update | **Low** | Run truncation command post-deploy |

---

## Post-Upgrade Cleanup

After a successful production deployment and stabilization period (1–2 weeks):

- [ ] Update `umd_docs/UmdCustomizations.md` to reflect v8.2 state
- [ ] Update `UpgradePlan-7.8-to-8.1.1.md` status if not already done
- [ ] Update version references in K8s `docs/Dependencies.md`
- [ ] Remove any `ACTIVE_RECORD_ENCRYPTION_MIGRATION` env var if it was temporarily set
- [ ] Assign proper unit admins to each unit in the admin dashboard
- [ ] Update this document with final image tags and deployment dates

---

## Related Documentation

- [UMD Customizations](./UmdCustomizations.md)
- [Avalon Permissions](./AvalonPermissions.md)
- [UMD Handle Integration](./UmdHandleIntegration.md)
- [Avalon Test Plan](./AvalonTestPlan.md)
- [Docker Development Environment](./DockerDevelopmentEnvironment.md)
- [Prior upgrade plan](./UpgradePlan-7.8-to-8.1.1.md)
- K8s upgrade plan: `k8s-infra-UpgradePlan-8.1.1-to-8.2.md` (in the `k8s-avalon` repo)

# Avalon Upgrade Plan: 7.8 → 8.1.1

## Overview

This document describes the plan for upgrading UMD's Avalon fork from **v7.8 (tag
`7.8.0-umd-4`)** to **upstream v8.1.1**, preserving all UMD customizations.

**Local strategy:** Incremental git merges (7.8→8.0→8.0.1→8.1→8.1.1) to manage conflict
surface area at each boundary.

**K8s strategy:** Single deployment jump directly from `7.8.0-umd-4` to `8.1.1-umd-0`.
Environments never run intermediate versions. For K8s-specific steps see the companion
document: `k8s-infra-UpgradePlan-7.8-to-8.1.1.md` (in the `k8s-avalon` repo).

| Release | Published | Key Changes |
|---------|-----------|-------------|
| v8.0 | 2024-12-09 | **Fedora 6**, Rails 7.2, Ruby 3.3, Debian Bookworm, Ramp 3.3 |
| v8.0.1 | 2025-05-02 | Bug fixes, item page load time improvements |
| v8.1 | 2025-08-28 | **Rails 8, Blacklight 8 (Bootstrap 5), Ruby 3.4, Ramp 4** |
| v8.1.1 | 2025-09-11 | Bug fixes (supplemental file metadata, typeahead, IIIF Content Search) |

Upstream release notes:
- <https://github.com/avalonmediasystem/avalon/releases/tag/v8.0>
- <https://github.com/avalonmediasystem/avalon/releases/tag/v8.0.1>
- <https://github.com/avalonmediasystem/avalon/releases/tag/v8.1>
- <https://github.com/avalonmediasystem/avalon/releases/tag/v8.1.1>

Upstream upgrade guides:
- [Upgrading 7.8 → 8.0](https://samvera.atlassian.net/wiki/spaces/AVALON/pages/2808086529/Upgrading+Avalon+7.8+to+Avalon+8.0)
- [Upgrading 8.0 → 8.0.1](https://samvera.atlassian.net/wiki/spaces/AVALON/pages/3167551489/Upgrading+Avalon+8.0+to+Avalon+8.0.1)
- [Upgrading 8.0.1 → 8.1](https://samvera.atlassian.net/wiki/spaces/AVALON/pages/3366322177/Upgrading+Avalon+8.0.1+to+Avalon+8.1)
- [Upgrading 8.1 → 8.1.1](https://samvera.atlassian.net/wiki/spaces/AVALON/pages/3385196545/Upgrading+Avalon+8.1.0+to+Avalon+8.1.1)

---

## Dependency Matrix

| Version | Ruby | Rails | Blacklight | Bootstrap | Ramp | Debian base |
|---------|------|-------|-----------|-----------|------|-------------|
| **Current (UMD 7.8)** | 3.2 | ~> 7.0.8 | ~> 7.25 | ~> 4.0 | 3.x | Bullseye |
| **8.0** | 3.3 | ~> 7.2 | ~> 7.x | ~> 4.0 | 3.3 | **Bookworm** |
| **8.1** | 3.4 | **~> 8.0** | **~> 8.10** | **~> 5.0** | **4** | Bookworm |
| **8.1.1** | 3.4 | ~> 8.0 | ~> 8.10 | ~> 5.0 | 4 | Bookworm |

---

## Breaking Changes Summary

| Area | Change | Risk |
|------|--------|------|
| **Fedora** | 4 → 6 (OCFL store) | **Critical** |
| **Ruby** | 3.2 → 3.4 | Low |
| **Rails** | ~> 7.0.8 → ~> 8.0 | High |
| **Blacklight** | ~> 7.25 → ~> 8.10 | High |
| **Bootstrap** | ~> 4.0 → ~> 5.0 (via Blacklight 8) | High |
| **Debian base** | Bullseye → Bookworm | Medium |
| **`react-rails`** | Replaced by `react_on_rails` | **High** |
| **`sass` / `sass-rails`** | Replaced by `sassc-rails` | Medium |
| **`redis-rails`** | Removed — subsumed by Rails 8 | Medium |
| **`mediainfo` gem** | Removed in v8.0 | Low |
| **Redis config** | host/port/db → URL format (required in v8.1) | Medium |
| **`hydra-head`** | ~> 12.0 → ~> 13.0 | Low |
| **`samvera-persona`** | ~> 0.4 → ~> 0.6 | Low |
| **`speedy-af`** | ~> 0.3 → ~> 0.5.0 | Low |
| **`noid-rails`** | ~> 3.1 → ~> 3.2 | Low |
| **`active_annotations`** | ~> 0.4 → ~> 0.6 | Low |
| **`active-fedora`** | ~> 14.0 → git ref (pending stable release) | Medium |
| **`avalon-about` tag** | `avalon-r7.7` → `avalon-r8.0` | Low |
| **`browse-everything` tag** | branch `v1.2-avalon` → tag `v1.5-Avalon` | Low |
| **`active_encode`** | >= 1.2.2 → ~> 1.3.0 | Low |
| **`omniauth-saml` version** | >= 2.2.1 → >= 2.2.3 | Low |
| **`puma`** | production group → top-level | Low |
| **DB migration** | `20240822194731` — safe NOT NULL relaxation on `active_storage_blobs.checksum` | None |

---

## UMD Customizations Inventory

All customizations below must be preserved through the upgrade.

### UMD-Only Gems

| Gem | Group | Purpose |
|-----|-------|---------|
| `sidekiq-limit_fetch` | default | Sidekiq queue concurrency limits |
| `health_check` | default | `/health_check` endpoint (K8s liveness probe) |
| `rbtrace ~> 0.5.3` | production | Ruby process tracing |

> **Pre-merge action:** Verify Rails 8 compatibility for `sidekiq-limit_fetch` and
> `health_check` before starting Phase 2. The K8s liveness probe depends on `health_check`.
> Check each gem's GitHub releases/issues for Rails 8 support.

### UMD Code Customizations

| Feature | Primary Files | Jira |
|---------|--------------|------|
| SAML/CAS Authentication | `config/settings.yml`, `config/initializers/devise.rb` | — |
| Access Tokens (JWT) | `app/models/access_token.rb`, `app/controllers/access_tokens_controller.rb` | LIBAVALON-198 |
| UMD IP Manager Integration | `app/services/umd_ip_manager.rb`, `app/models/ability.rb` | — |
| Master File Downloads | `app/controllers/master_files_controller.rb`, `app/models/master_file.rb` | LIBAVALON-398 |
| Restricted Playback / Jim Henson msg | `app/javascript/components/UmdRestrictedPlayback.jsx`, `app/models/ability.rb` | LIBAVALON-403 |
| Aeon "Request from Special Collections" | `app/views/media_objects/show.html.erb` | LIBAVALON-93 |
| UMD Handle Integration | `app/services/umd_handle.rb`, `app/controllers/media_objects_controller.rb` | — |
| Course Reserves / Course Name Facet | `app/controllers/catalog_controller.rb`, `app/models/course.rb`, `app/views/collections/course_reserves.html.erb` | LIBAVALON-438 |
| Matomo Analytics | `app/views/modules/_matomo_analytics.html.erb`, `app/views/layouts/avalon.html.erb` | — |
| Docker jemalloc / YJIT / Puma tuning | `Dockerfile` | — |
| S3 Archive / Master File Management | `app/jobs/migrate_to_s3_job.rb`, `lib/tasks/migrate_to_s3.rake` | — |
| UMD IP Manager Leases | `app/models/lease.rb`, `app/models/access_control_step.rb` | — |
| Streaming Reserves | `app/models/media_object.rb` (`is_streaming_reserve?`) | LIBAVALON-168 |

> See [UmdCustomizations.md](./UmdCustomizations.md) for detailed descriptions of each feature.

---

## Phase 0 — Preparation

### 0.1 Pre-Upgrade Verification

```bash
# Confirm section_list migration has been run (required before Fedora migration)
# Check via Rails console or schema_migrations table:
bundle exec rails runner "puts MediaObject.where(section_list: nil).count"
# Expected: 0 (all objects have section_list populated)

# Confirm Solr is on version 9
# (Solr 6 configs are removed in v8.0 — must be upgraded before merging)
curl http://solr:8983/solr/admin/info/system | jq '.lucene."solr-spec-version"'
```

### 0.2 Gem Compatibility Pre-Check

Before any merging, verify Rails 8 support for UMD-specific gems:

- `sidekiq-limit_fetch`: <https://github.com/brainopia/sidekiq-limit_fetch>
- `health_check`: <https://github.com/ianheggie/health_check>
- `rbtrace`: <https://github.com/tmm1/rbtrace>

### 0.3 Backups

```bash
# Database dump
pg_dump avalon_production > avalon_production_7.8.0-umd-4_backup.sql

# Active Storage supplemental files (before destroying the container)
docker cp avalon-docker-avalon-1:/home/app/avalon/storage ./active_storage_backup
# Load into S3 bucket:
aws s3 cp active_storage_backup/* s3://${SETTINGS__ACTIVE_STORAGE__BUCKET}/ --recursive
```

### 0.4 Create Upgrade Branch

We use **merge** (not rebase) to preserve Git history and keep UMD commits traceable.

```bash
cd /path/to/umd-lib/avalon

# Add upstream remote if not present
git remote add upstream https://github.com/avalonmediasystem/avalon.git
git fetch upstream --tags

# Verify starting point
git branch           # should be on: avalon-main
git describe --tags  # should show: 7.8.0-umd-4

# Audit UMD commit delta before merging
git log upstream/v7.8..avalon-main --oneline
git diff upstream/v7.8 avalon-main --name-only

# Create upgrade branch
git checkout avalon-main
git checkout -b release/8.1.1-umd-0
```

### 0.5 Baseline Test Run

```bash
bundle exec rspec   # establish a passing baseline before any changes
```

---

## Phase 1 — Infrastructure: Fedora 4 → 6 Migration

> **This must be completed before merging v8.0.** The Fedora migration is irreversible.
> Perform all steps inside the running Avalon container. Take backups first (Phase 0.3).

### 1.1 Set Up Java and Migration Tools

```bash
# Inside avalon container
cd /tmp && mkdir fc4_to_fc6 && cd fc4_to_fc6

# Install JDK 21
curl -O -L https://download.java.net/java/GA/jdk21/fd2272bbf8e04c3dbaee13770090416c/35/GPL/openjdk-21_linux-x64_bin.tar.gz
tar xvzf openjdk-21_linux-x64_bin.tar.gz

# Download import/export tool (specific version required)
curl -O -L https://github.com/fcrepo-exts/fcrepo-import-export/releases/download/fcrepo-import-export-1.2.0/fcrepo-import-export-1.2.0.jar

# Download upgrade-utils (Avalon-specific build)
curl -O -L https://github.com/avalonmediasystem/fcrepo-upgrade-utils/releases/download/6.3.0-AVALON/fcrepo-upgrade-utils-6.3.0-AVALON.jar
```

### 1.2 Export Fedora 4

```bash
jdk-21/bin/java -jar fcrepo-import-export-1.2.0.jar -b \
  --dir fcrepo4.7.5_export \
  --user fedoraAdmin:fedoraAdmin \
  --mode export \
  --resource http://fedora:8080/fedora/rest \
  --binaries --membership --auditLog \
  > importexport_`date +%Y%m%dT%H%M%S`.log 2>&1

# Verify: log should contain "(Exporter) Export complete"
# If a remaining_*.log file exists, the export did not finish cleanly.
# Resume with: --resourcesFile remaining_TIMESTAMP.log
```

### 1.3 Migrate F4 → F5 → F6

```bash
# Fedora 4 → Fedora 5
jdk-21/bin/java -jar fcrepo-upgrade-utils-6.3.0-AVALON.jar \
  --input-dir fcrepo4.7.5_export \
  --output-dir fcrepo5_export \
  --source-version 4.7.5 \
  --target-version 5+ \
  > upgrade_5_`date +%Y%m%dT%H%M%S`.log 2>&1

# Fedora 5 → Fedora 6
jdk-21/bin/java --add-opens java.base/java.util.concurrent=ALL-UNNAMED \
  -jar fcrepo-upgrade-utils-6.3.0-AVALON.jar \
  --input-dir fcrepo5_export \
  --output-dir fcrepo6_export \
  --source-version 5+ \
  --target-version 6+ \
  --base-uri http://fedora:8080/fedora/rest \
  > upgrade_6_`date +%Y%m%dT%H%M%S`.log 2>&1

# To resume a failed migration pass: --resource-info-file remaining_TIMESTAMP.log
```

### 1.4 Back Up and Extract Migrated Data

```bash
# Tar up all exports for backup (still inside container)
tar cvzf fcrepo4_export.tgz fcrepo4.7.5_export
tar cvzf fcrepo5_export.tgz fcrepo5_export
tar cvzf fcrepo6_export.tgz fcrepo6_export

# Copy migrated data out of container (run from host)
docker cp avalon-docker-avalon-1:/tmp/fc4_to_fc6/fcrepo6_export/data fedora_data

# Push to S3
aws s3 sync fedora_data/ocfl-root s3://avalon-fedora-ocfl/
aws s3 sync /tmp/fc4_to_fc6/ s3://avalon-fedora-ocfl/backups/
```

### 1.5 Provision Fedora 6

Set up the Fedora 6 container pointing at the OCFL data store. Restart and verify object
count matches Fedora 4 before proceeding to Phase 2.

---

## Phase 2 — Merge v8.0

```bash
git merge upstream/v8.0 --no-ff -m "Merge upstream Avalon v8.0 into release/8.1.1-umd-0"
# Resolve conflicts — see guidance below
git add -A && git commit
```

### 2.1 Dockerfile — Bullseye → Bookworm + Ruby 3.3

```dockerfile
# Change ALL occurrences in Dockerfile and Dockerfile.dev:
#   ruby:3.2-bullseye        → ruby:3.3-bookworm
#   ruby:3.2-slim-bullseye   → ruby:3.3-slim-bookworm
# Update any "bullseye" references in apt source lines to "bookworm"
```

Also update `.ruby-version` to `3.3` and Node.js to 20 in both Dockerfiles.

### 2.2 Gemfile — v8.0 Changes

Remove (dropped in v8.0):
```ruby
gem 'mediainfo', git: "https://github.com/avalonmediasystem/mediainfo.git", tag: 'v0.7.1-avalon'
```

### 2.3 High-Conflict UMD Files

| File | Conflict Risk | What to Preserve |
|------|--------------|-----------------|
| `app/models/ability.rb` | High | All streaming reserves (LIBAVALON-168), access token, and master file download permission blocks |
| `app/javascript/components/MediaObjectRamp.jsx` | High | Ramp 3.3 refactored state management; expand/collapse moved into Ramp component itself. Re-apply UMD blocks at lines 26-32, 59-64, 76-88, 183-188, 279-290, 294-296, 306-318 |
| `app/models/media_object.rb` | Medium | `is_streaming_reserve?` method; `course_title_ssim` Solr field; Streaming Reserves discovery group logic |
| `app/controllers/catalog_controller.rb` | Medium | Course Name facet config; UMD IP Manager group facet handling |
| `config/settings.yml` | Medium | All UMD blocks: auth, `streaming_reserves.unit_name`, S3 master file management |

### 2.4 Config Updates

```yaml
# config/settings.yml — new optional setting in v8.0:
ffprobe:
  path: '/usr/bin/ffprobe'
```

Verify `solr/` directory contains only Solr 9 configs (Solr 6 configs removed in v8.0).

```bash
bundle install && yarn install
bundle exec rake db:migrate
bundle exec rspec spec/models/ability_spec.rb spec/controllers/access_tokens_controller_spec.rb
```

---

## Phase 3 — Merge v8.0.1

```bash
git merge upstream/v8.0.1 --no-ff -m "Merge upstream Avalon v8.0.1 into release/8.1.1-umd-0"
# Bug-fix release — minimal conflicts expected
git add -A && git commit
```

**Google Drive remediation (if applicable):**
If UMD has ever ingested files via Google Drive browse-everything, find affected masterfiles
before deploying:
```ruby
# Rails console
ActiveFedora.solr.conn.get('select', params: {
  q: 'has_model_ssim:MasterFile AND file_location_ssi:/https\:\/\/www.googleapis.com.*/',
  rows: 1_000_000, fl: [:id]
})
# Remediate any results per upstream guidance before deploying
```

```bash
bundle install && yarn install && bundle exec rake db:migrate
bundle exec rspec
```

---

## Phase 4 — Merge v8.1 (Largest Change)

```bash
git merge upstream/v8.1 --no-ff -m "Merge upstream Avalon v8.1 into release/8.1.1-umd-0"
# Largest conflict set — Rails 8, Bootstrap 5, react_on_rails, Redis URL
```

### 4.1 Gemfile — Full Conflict Resolution

**Remove (replaced or subsumed):**
```ruby
gem 'redis-rails'      # subsumed by Rails 8
```

**Update version constraints:**
```ruby
gem 'rails', '~> 8.0'
gem 'bootstrap', '~> 5.0'
gem 'blacklight', '~> 8.10'
gem 'blacklight-access_controls', '~> 6.1'
gem 'hydra-head', '~> 13.0'
gem 'samvera-persona', '~> 0.6'
gem 'speedy-af', '~> 0.5.0'
gem 'noid-rails', '~> 3.2'
gem 'active_annotations', '~> 0.6'
gem 'active_encode', '~> 1.3.0'
gem 'omniauth-saml', '~> 2.0', '>= 2.2.3'
gem 'avalon-about', git: 'https://github.com/avalonmediasystem/avalon-about.git', tag: 'avalon-r8.0'
gem 'browse-everything', git: 'https://github.com/avalonmediasystem/browse-everything', tag: 'v1.5-Avalon'
gem 'react_on_rails'       # replaces react-rails
gem 'sassc-rails'          # replaces sass 3.4.22
gem 'puma', '>= 6.4.2'    # move to top-level (out of production group)
```

**Restore UMD-only gems** (add back if swept away by merge):
```ruby
# UMD Customization
gem 'sidekiq-limit_fetch'
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
# Review Gemfile.lock for unexpected regressions
git add Gemfile Gemfile.lock
git commit -m "UMD: Update Gemfile for Rails 8 / Avalon 8.1.1 compatibility"
```

### 4.2 Dockerfile — Ruby 3.4 + jemalloc Reconciliation

```dockerfile
# Update ALL base image references:
#   ruby:3.3-bookworm        → ruby:3.4-bookworm
#   ruby:3.3-slim-bookworm   → ruby:3.4-slim-bookworm
```

Update `.ruby-version` to `3.4`.

Upstream v8.1.1 now sets `LD_PRELOAD`, `MALLOC_CONF` (`narenas:2,...`), and
`RUBY_YJIT_ENABLE` in the bundle stage. Remove UMD duplicates from the production
stage to avoid conflicts, but keep UMD-specific Puma tuning:

```dockerfile
# Remove from production stage (now set upstream in bundle stage):
#   LD_PRELOAD, RUBY_YJIT_ENABLE, MALLOC_CONF

# UMD Customization
# Puma worker tuning (K8s configmap overrides MALLOC_CONF at runtime — see k8s plan Phase 1.2)
ENV PUMA_WORKERS=4
ENV RAILS_MAX_THREADS=5
# End UMD Customization
```

> **Note:** The K8s configmap sets `MALLOC_CONF=narenas:4,dirty_decay_ms:30000,...`
> which overrides the Dockerfile `ENV` at runtime. See `k8s-infra-UpgradePlan-7.8-to-8.1.1.md`
> Phase 1.2 for the decision on whether to keep UMD's production tuning or align to upstream's
> `narenas:2`. Add a comment in the Dockerfile documenting the K8s override.

### 4.3 Rails 8 Compatibility

Review `config/initializers/devise.rb` — the intentionally-commented-out
`Rails.application.reloader.to_prepare` block. Rails 8 may change OmniAuth mounting
behavior. **Test SAML login in the test environment before proceeding to QA.**

Review `config/application.rb` and `config/environments/{production,development}.rb`
UMD blocks for incompatibility with Rails 8 defaults.

### 4.4 Breaking Config: Redis URL Format (Required in v8.1)

Upstream v8.1 requires a full Redis URL. Test in the K8s test environment first to
confirm whether the existing UMD host/port/db format still works with Rails 8 / Sidekiq.
If Sidekiq fails to connect, switch to URL format:

In `config/settings.yml` (local dev / Docker):
```yaml
# UMD Customization
redis:
  url: 'redis://redis:6379/0'
# End UMD Customization
```

In K8s `base/configs/settings.yml` (see K8s plan Phase 2.2):
```yaml
# UMD Customization
redis:
  url: 'redis://avalon-redis:6379/0'
# End UMD Customization
```

Also update `docker-compose.yml` and `env_template`.

### 4.5 `react-rails` → `react_on_rails` (All UMD Components)

The ERB view helper call (`react_component`) stays the same. What changes is the JS
registration. First, audit all usages:

```bash
grep -r "react_component" app/views/ app/helpers/ --include="*.erb" --include="*.rb" -n
```

Update the `app/javascript/packs/` entry point(s) to explicitly register all UMD components:

```js
// react-rails (OLD): components auto-discovered via react_ujs — no registration needed

// react_on_rails (NEW): explicit registration required
import ReactOnRails from 'react-on-rails';
import UmdRestrictedPlayback from '../components/UmdRestrictedPlayback';
import UmdMasterFiles from '../components/UmdMasterFiles';
import UmdCopyHandleUrlButton from '../components/UmdCopyHandleUrlButton';
import UmdMetadataDisplay from '../components/UmdMetadataDisplay';
import UMDFacetFilter from '../components/UMDFacetFilter';
import MediaObjectRamp from '../components/MediaObjectRamp';
import CollectionList from '../components/CollectionList';

ReactOnRails.register({
  UmdRestrictedPlayback,
  UmdMasterFiles,
  UmdCopyHandleUrlButton,
  UmdMetadataDisplay,
  UMDFacetFilter,
  MediaObjectRamp,
  CollectionList,
});
```

### 4.6 Bootstrap 4 → Bootstrap 5 View Updates

Find all Bootstrap 4 patterns in UMD views:

```bash
# Data attributes (renamed in Bootstrap 5)
grep -r "data-toggle\|data-dismiss\|data-target\|data-ride\|data-spy" \
  app/views/ --include="*.erb" -l

# Spacing utilities (renamed in Bootstrap 5)
grep -r "\bml-\|\bmr-\|\bpl-\|\bpr-\|\bfloat-left\|\bfloat-right\|\btext-left\|\btext-right" \
  app/views/ --include="*.erb" -l

# Removed classes
grep -r "form-group\|sr-only\|badge-" app/views/ --include="*.erb" -l
```

Bootstrap 4 → 5 replacements:

| Bootstrap 4 | Bootstrap 5 | Notes |
|-------------|-------------|-------|
| `data-toggle="modal"` | `data-bs-toggle="modal"` | All interactive components |
| `data-dismiss="modal"` | `data-bs-dismiss="modal"` | Close buttons |
| `data-target="#id"` | `data-bs-target="#id"` | All targets |
| `data-toggle="collapse"` | `data-bs-toggle="collapse"` | Accordions |
| `data-toggle="tooltip"` | `data-bs-toggle="tooltip"` | Tooltips |
| `data-toggle="dropdown"` | `data-bs-toggle="dropdown"` | Dropdowns |
| `mr-{n}` / `ml-{n}` | `me-{n}` / `ms-{n}` | Margin end / start |
| `pr-{n}` / `pl-{n}` | `pe-{n}` / `ps-{n}` | Padding end / start |
| `float-left` / `float-right` | `float-start` / `float-end` | Floats |
| `text-left` / `text-right` | `text-start` / `text-end` | Text align |
| `form-group` | `mb-3` (or remove) | Form layout |
| `badge-{color}` | `bg-{color} text-{color}` | Badges |
| `sr-only` | `visually-hidden` | Screen reader text |

UMD-specific views requiring full audit:

- `app/views/layouts/avalon.html.erb` — UMD header, Matomo script tag
- `app/views/layouts/embed.html.erb`
- `app/views/collections/course_reserves.html.erb` — UMD-only view
- `app/views/catalog/_document_list.html.erb`
- `app/views/_user_util_links.html.erb` — access tokens link, courses impersonation
- `app/views/modules/_header.html.erb` — UMD Digital Collections logo
- `app/views/modules/_matomo_analytics.html.erb` — UMD-only partial
- `app/views/modules/_become_message.html.erb`
- `app/views/media_objects/show.html.erb` — Aeon "Request from Special Collections" button
- `app/views/devise/sessions/new.html.erb` — SAML login message

Also audit `app/javascript/components/UMDFacetFilter.jsx` — Blacklight 8 renders its
"More" facet modal under Bootstrap 5; the component targets Blacklight-rendered DOM nodes
that may have changed structure.

### 4.7 Blacklight 8 Catalog Controller

Update UMD facet and search customizations in `app/controllers/catalog_controller.rb`
for the Blacklight 8 API. The facet config DSL and search field configuration syntax
may differ from Blacklight 7.

### 4.8 Ramp 4 Migration

Review the [Ramp 4.0.0 release notes](https://github.com/samvera-labs/ramp/releases)
**before** modifying `app/javascript/components/MediaObjectRamp.jsx`. Re-apply all UMD
customizations under Ramp 4's updated component API; verify prop contracts for:

- `UmdRestrictedPlayback` render integration
- `UmdMasterFiles` tab integration
- `UmdCopyHandleUrlButton` and `UmdMetadataDisplay` positioning

### 4.9 Optional New Settings (v8.1)

```yaml
# config/settings.yml
email:
  # ...
  # UMD Customization
  # Optional: surface an accessibility request link under the media player
  # accessibility_request_link: 'https://example.umd.edu/a11y-form'
  # End UMD Customization
```

> **AWS SES email users only:** If Avalon is configured with `:aws_sdk` as the mail
> delivery method, apply changes from upstream PR #6573 before deploying. This is a
> known startup-breaking issue not fixed until v8.2.

```bash
bundle install && yarn install
bundle exec rake db:migrate    # picks up migration 20240822194731
bundle exec rspec              # fix iteratively
git add -A && git commit
```

---

## Phase 5 — Merge v8.1.1

```bash
git merge upstream/v8.1.1 --no-ff -m "Merge upstream Avalon v8.1.1 into release/8.1.1-umd-0"
# Bug-fix only — no dependency changes
git add -A && git commit
```

```bash
bundle install && yarn install && bundle exec rake db:migrate
bundle exec rspec

# Specifically verify the two targeted bug fixes:
# 1. Supplemental file metadata saves correctly
# 2. Typeahead/autocomplete form fields work (course title, subjects, etc.)
```

---

## Phase 6 — Build & Tag

> **M-series Mac:** Build Docker images in the Kubernetes cluster, not locally, to ensure
> correct `amd64` architecture.
> See <https://github.com/umd-lib/k8s/blob/main/docs/DockerBuilds.md>.

```bash
# RC build
docker build -t docker.lib.umd.edu/avalon:8.1.1-umd-0-rc1 .
docker push docker.lib.umd.edu/avalon:8.1.1-umd-0-rc1

# After test/QA sign-off — release build
docker build -t docker.lib.umd.edu/avalon:8.1.1-umd-0 .
docker push docker.lib.umd.edu/avalon:8.1.1-umd-0

# Tag the Git release
git tag 8.1.1-umd-0
git push origin release/8.1.1-umd-0 --tags
```

---

## Phase 7 — K8s Deployment (Single Jump 7.8 → 8.1.1)

> Full K8s-side steps (configmap, settings.yml, Solr config, overlay updates, production
> runbook) are in: **`k8s-infra-UpgradePlan-7.8-to-8.1.1.md`** in the `k8s-avalon` repo.

### Pre-Deploy Checklist (app repo side)

- [ ] Confirm whether `SETTINGS__FFMPEG__PATH` K8s configmap override is still needed.
  Check if upstream PR #6467 merged in v8.1.1:
  ```bash
  curl -s https://api.github.com/repos/avalonmediasystem/avalon/pulls/6467 | jq '.merged_at'
  ```
- [ ] Redis URL format decision confirmed (Phase 4.4 test result applied)
- [ ] `MALLOC_CONF` conflict decision documented (Dockerfile comment + K8s plan Phase 1.2)
- [ ] `ffprobe.path` added to K8s `base/configs/settings.yml`
- [ ] `course_title_ssim` field verified present in K8s `base/configs/solr/conf/schema.xml`

### Rollout Order

Deploy to each K8s environment in sequence; do not promote until tests pass:

1. **test** — functional and Bootstrap 5 UI regression testing (use RC image `8.1.1-umd-0-rc1`)
2. **qa** — stakeholder acceptance testing
3. **sandbox** — if applicable
4. **prod** — production deployment (use release image `8.1.1-umd-0`; follow K8s plan Phase 5)

After each deployment, trigger a full Solr reindex:

```bash
kubectl exec -it avalon-0 -c avalon -- bash -c "bundle exec rake avalon:reindex"
# Verify the Course Name facet returns results in the UI
```

---

## Testing Checklist

### Local Spec Suite (after Phase 5)

- [ ] `bundle exec rspec` — full suite passes
- [ ] `bundle exec rspec spec/models/ability_spec.rb` — UMD permission model intact
- [ ] `bundle exec rspec spec/controllers/access_tokens_controller_spec.rb`
- [ ] `bundle exec rspec spec/models/media_object_spec.rb` — Solr indexing

### UMD Feature Regression (K8s test environment)

- [ ] SAML/CAS login works in Chrome; `SAML_ISSUER`, `SAML_SP_PRIVATE_KEY`,
  `SAML_SP_CERTIFICATE` env vars respected
  *(Firefox login remains broken with `av-local` due to SameSite cookie — use Chrome)*
- [ ] Access token creation → streaming grant → download grant work end-to-end
- [ ] UMD IP Manager groups apply correctly to streaming access
- [ ] Users with `master_file_download` permission see master files in the Files tab;
  users without the permission do NOT
- [ ] Restricted playback message appears for VPN-restricted items
- [ ] Jim Henson collection shows its distinct message
  (configured via `SETTINGS__JIM_HENSON_COLLECTION__MATCH_STRING`)
- [ ] "Request from Special Collections" Aeon button appears and pre-populates the form
- [ ] Publishing an item triggers handle minting via the `umd-handle` service
- [ ] `course_title_ssim` Course Name facet appears in Blacklight search results
- [ ] `UMDFacetFilter` case-insensitive substring filter works in the "More" facet dialog
- [ ] Matomo tracking fires when env vars are set; is absent when they are not
- [ ] `/health_check` returns `success` (K8s liveness probe depends on this)

### Bootstrap 5 / Rails 8 Regression

- [ ] All modal dialogs open and close correctly (Bootstrap 5 `data-bs-*` attributes)
- [ ] Access control step UI renders correctly (access token panel, IP manager group panel)
- [ ] Share panel enables on item pages
- [ ] Typeahead/autocomplete fields work (course title, subjects, etc.) — fixed in v8.1.1
- [ ] Supplemental file metadata saves correctly — fixed in v8.1.1
- [ ] IIIF Content Search returns valid response when no parameters are provided — fixed in v8.1.1
- [ ] HLS streaming and stream token validation work
- [ ] Sidekiq queues process (`create_encode`, `waveform`, `default`, `batch_ingest`)
- [ ] Asset pipeline compiles without errors (`sassc-rails` replacing `sass`)
- [ ] Solr reindex completes; Course Name facet returns results

### Database Migration Verification

```bash
kubectl exec -it avalon-db-0 -- psql -U avalon -d avalon \
  -c "SELECT version FROM schema_migrations WHERE version = '20240822194731';"
# Expected: one row returned
```

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Fedora 4→6 migration data loss | **Critical** | Full backup before Phase 1; verify object count after migration |
| Bootstrap 4→5 breaking UMD custom views | **High** | Run grep audit commands; full UI regression in test before QA |
| `react-rails` → `react_on_rails` component registration | **High** | Audit all `react_component` calls; update all JS pack entry points |
| OmniAuth SAML + Rails 8 CSRF compatibility | **Medium** | Test SAML login in isolated test environment first (Phase 4.3) |
| `sidekiq-limit_fetch` Rails 8 incompatibility | **Medium** | Check GitHub issues pre-merge; test encode queue behavior in test |
| `health_check` Rails 8 incompatibility | **Medium** | Verify `/health_check` route early — K8s liveness probe depends on it |
| Redis config format breaking Sidekiq | **Medium** | Test existing host/port format in test K8s first; switch to URL if broken |
| Ramp 4 breaking `MediaObjectRamp.jsx` integrations | **Medium** | Read Ramp 4 changelog before touching the component (Phase 4.8) |
| `MALLOC_CONF` conflict (Dockerfile vs K8s configmap) | **Low** | Configmap always wins at runtime; document decision with a comment |
| Solr schema drift losing Course Name facet | **Low** | Diff `schema.xml` before/after merge; reindex post-deploy |

---

## Post-Upgrade Cleanup

After a successful production deployment and a stabilization period (1–2 weeks):

- [ ] Remove `SETTINGS__FFMPEG__PATH` from K8s `base/configmap.yaml` if confirmed unnecessary
- [ ] Update `umd_docs/UmdCustomizations.md` to reflect the 8.1.1 state
- [ ] Update version references in K8s `docs/Dependencies.md`
- [ ] Run `list-resources.sh` in the k8s-avalon repo; update `docs/Resources.md` if any
  K8s resources changed
- [ ] Update this document and `k8s-infra-UpgradePlan-7.8-to-8.1.1.md` with final image
  tags and deployment dates

---

## Related Documentation

- [UMD Customizations](./UmdCustomizations.md)
- [Avalon Permissions](./AvalonPermissions.md)
- [UMD Handle Integration](./UmdHandleIntegration.md)
- [Avalon Test Plan](./AvalonTestPlan.md)
- [Docker Development Environment](./DockerDevelopmentEnvironment.md)
- K8s upgrade plan: `k8s-infra-UpgradePlan-7.8-to-8.1.1.md` (in the `k8s-avalon` repo)

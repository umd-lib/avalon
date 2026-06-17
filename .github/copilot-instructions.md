# GitHub Copilot Instructions - Avalon (UMD fork)

## Project Overview

This is **Avalon Media System**, an open-source Rails application for managing large collections of digital audio and video, originally developed by Indiana University Libraries. This repository is the **University of Maryland (UMD) fork** (`umd-lib/avalon`), which extends upstream `avalonmediasystem/avalon` with institutional customizations.

- **Primary language:** Ruby (Rails 8.0.x), Ruby 3.4
- **Frontend:** CoffeeScript, ES6/JSX (React via `react_on_rails` v14 + Shakapacker), Bootstrap 5
- **Persistence:** Fedora 6 OCFL (via ActiveFedora), Apache Solr (via Blacklight 8), SQLite/PostgreSQL/MySQL, Redis
- **Background jobs:** Sidekiq 6 with `sidekiq-cron` and `sidekiq-limit_fetch`
- **Auth:** Devise + OmniAuth; UMD uses SAML via CAS (`omniauth-saml`)
- **Storage:** Local filesystem or AWS S3; CloudFront signing for streaming
- **Deployment:** Docker / Kubernetes (UMD); AWS Elastic Beanstalk (upstream)

---

## Repository Layout

```
avalon/
+-- app/
|   +-- assets/          # Sprockets - legacy JS (CoffeeScript, .es6), CSS, images
|   +-- javascript/      # Shakapacker - modern React components (JSX)
|   |   +-- components/  # React components (many UMD-specific)
|   |   +-- packs/       # Webpack entry points
|   +-- controllers/     # Rails controllers
|   +-- models/          # ActiveFedora + ActiveRecord models
|   +-- jobs/            # ActiveJob / Sidekiq workers
|   +-- services/        # Plain Ruby service objects
|   +-- presenters/      # Presenter objects (IIIF, SpeedyAF)
|   +-- validators/      # Custom ActiveModel validators
|   +-- mailers/         # ActionMailer classes
|   +-- views/           # ERB templates
+-- config/
|   +-- settings.yml     # Main config (uses `config` gem; overridable via ENV)
|   +-- routes.rb        # All routes including UMD additions
|   +-- initializers/    # Rails initializers (Devise/SAML quirks documented in UMD-README)
|   +-- settings/        # Environment-specific overrides (development.local.yml)
+-- spec/                # RSpec tests
+-- umd_docs/            # UMD-only documentation - read before modifying UMD features
|   +-- UmdCustomizations.md
|   +-- AvalonPermissions.md
|   +-- DockerDevelopmentEnvironment.md
|   +-- AvalonTestPlan.md
+-- Gemfile
+-- Dockerfile           # Multi-stage production build (ruby:3.4-bookworm)
+-- Dockerfile.dev
+-- docker-compose.yml
```

---

## Core Domain Models

Understanding these models is essential before modifying any feature:

| Model | Description |
|---|---|
| `MediaObject` | Top-level A/V item. Backed by ActiveFedora (Fedora). Has MODS metadata, workflow state, visibility, and one or more `MasterFile` sections. |
| `MasterFile` | A single audio/video file (section) within a `MediaObject`. Holds encode state, structural metadata, captions, waveform, derivatives. |
| `Derivative` | A transcoded rendition of a `MasterFile` (HLS, RTMP). |
| `Admin::Collection` | Groups `MediaObject`s. Controls default visibility, units, dropbox path, and S3 bucket. |
| `Playlist` / `PlaylistItem` | User-curated lists of `AvalonClip`s. |
| `Timeline` | IIIF-based annotation timeline tied to a `MasterFile`. |
| `SupplementalFile` | Auxiliary files (captions, transcripts) attached to a `MediaObject` or `MasterFile`. |
| `AccessToken` | **UMD custom.** JWT-based token granting stream/download access to a published item. |
| `Course` | **UMD custom.** Maps LTI context IDs to course titles for the Course Reserves facet. |
| `Lease` | Time-bounded access grant for groups/users/IPs. |
| `StreamToken` | Short-lived token used to authorize a streaming request. |

---

## UMD Customizations - Critical Context

All UMD-specific changes are wrapped with comments:

```ruby
# UMD Customization
... modified code ...
# End UMD Customization
```

**Always preserve these markers** when editing existing files. When adding new UMD-specific code, wrap it with these markers.

### Key UMD Features

1. **SAML Authentication** - Login via UMD CAS (`omniauth-saml`). Uses `av-local` hostname in development (not `localhost`). See `config/settings.yml` `auth:` block and `umd_docs/DockerDevelopmentEnvironment.md`.

2. **Access Tokens** - JWT-based time-limited tokens granting `stream`, `download`, or `stream_and_download` permission. Model: `AccessToken`. Controller: `AccessTokensController`. Route: `resources :access_tokens`.

3. **UMD IP Manager** - Service `UmdIpManager` integrates with an external REST API to resolve IP address group membership. Groups use the prefix `umd.ip.manager:`. Configured via `IP_MANAGER_SERVER_URL` and `IP_MANAGER_TIMEOUT` env vars.

4. **Modified Permission Model** - Diverges from stock Avalon. Published = viewable by all. Streaming is controlled separately by `visibility`. See `umd_docs/AvalonPermissions.md` before modifying `ability.rb` or `MediaObject#to_solr`.

5. **Master File Downloads** - Users with `master_file_download` permission can download master files via the Files tab (`UmdMasterFiles.jsx` component).

6. **Aeon Integration** - Request from Special Collections button (`AeonRequestForm.jsx`) submits a POST to Aeon with item metadata.

7. **Restricted Playback** - `UmdRestrictedPlayback.jsx` shows a VPN/contact message when media is inaccessible. Jim Henson collection shows a distinct message (configurable via `SETTINGS__JIM_HENSON_COLLECTION__MATCH_STRING`).

8. **Course Reserves** - `course_title_ssim` Solr field and `UMDFacetFilter.jsx` React component for case-insensitive facet filtering.

9. **Matomo Analytics** - Enabled when `MATOMO_ANALYTICS_URL`, `MATOMO_ANALYTICS_SITE_ID`, and `MATOMO_ANALYTICS_CDN_SRC` are all set.

10. **Handle Integration** - Permalink generation via `umd-handle` REST API (`UMD_HANDLE_SERVER_URL` + `UMD_HANDLE_JWT_TOKEN`). See `umd_docs/UmdHandleIntegration.md`.

11. **S3 and Archive Management** - `master_file_management.strategy: move` automatically archives ingested master files. Rake task `umd:move_dropbox_files_to_archive` handles legacy migration.

12. **Streaming Reserves** - Unit named `streaming_reserves.unit_name` (default: `Streaming Reserves`) receives special `discover` group behavior; see `MediaObject#to_solr` `is_streaming_reserve?` check.

---

## Configuration

Configuration uses the `config` gem. `config/settings.yml` is the base; environment-specific overrides go in `config/settings/development.local.yml` (git-ignored). Any key can be overridden via environment variable using double-underscore notation:

```
SETTINGS__STREAMING__SERVER=aws
SETTINGS__JIM_HENSON_COLLECTION__MATCH_STRING=henson collection
```

| Section | Purpose |
|---|---|
| `auth.configuration` | OmniAuth providers (SAML for UMD) |
| `streaming` | Server type (`:generic`, `:aws`), token TTL, base URLs |
| `dropbox.path` | Ingest dropbox root (`/masterfiles/dropbox` in UMD) |
| `master_file_management` | `strategy: move` plus archive `path` |
| `bib_retriever` | SRU endpoint for bibliographic import (UMD: USMAI Alma) |
| `derivative.allow_download` | Enable derivative downloads for managers/admins |
| `controlled_digital_lending` | CDL feature flag and defaults |

---

## Code Style & Linting

### Ruby

- Linter: **RuboCop** via `bixby` (inherits `bixby_default.yml`). Run: `bundle exec rubocop`
- `Metrics/MethodLength` max: **15** (comments excluded). `Metrics/LineLength` is **disabled**.
- Hash syntax: **Ruby 1.9 style** (`key: value`). No hash rockets unless the value is a symbol.
- Excluded from linting: `db/`, `spec/fixtures/`, `vendor/`, `tmp/`, `log/`, `coverage/`.
- Do **not** introduce new `# rubocop:disable` comments without justification.
- All Ruby source files must start with the Apache 2.0 license header (see `LICENSE_HEADER`).
- New UMD-only Ruby files should include `# frozen_string_literal: true` at the top.

### JavaScript / JSX

- Linter: **ESLint** (config: `.eslintrc`). Formatter: **Prettier** (config: `.prettierrc`).
- Prettier settings: `singleQuote: true`, `tabWidth: 2`, `printWidth: 80`, `semi: true`.
- Run lint: `eslint app/assets/javascripts/ --ext .js,.es6`
- Run format: `prettier --write "app/javascript/**/*.{js,jsx}"`
- `complexity` rule max: **6**. `max-statements` max: **30**.
- Environments: `browser`, `es6`, `jquery`, `node`, `amd`. JSX support enabled.
- Use `const`/`let` (not `var`), strict equality (`===`), arrow functions. No `alert()`, no `eval()`.

---

## Testing

- Framework: **RSpec** (`spec/rails_helper.rb`, `spec/spec_helper.rb`)
- Factories: **FactoryBot** (`spec/factories/`)
- Feature specs: **Capybara** + **Selenium** (Chrome)
- E2E: **Cypress** (`spec/cypress/`)
- Coverage: **SimpleCov** + CodeClimate

### Running Tests (Docker)

```bash
# Start test stack
docker-compose up test

# Run all specs (takes ~5 hours - avoid during normal development)
docker-compose exec test bash -c "bundle exec rspec"

# Run a single spec file (preferred)
docker-compose exec test bash -c "bundle exec rspec spec/controllers/access_tokens_controller_spec.rb"
```

### Writing Tests

- Place specs mirroring the source: `spec/controllers/`, `spec/models/`, `spec/services/`.
- Use `let` / `let!` and FactoryBot (`create`, `build`). Avoid `before(:all)`.
- `RSpec/MultipleExpectations` is disabled - multiple `expect` calls per example are allowed.
- Use `webmock` to stub all external HTTP calls (IP Manager, Handle server, Aeon, etc.).
- Tag slow integration tests with `:integration` and browser tests with `:feature`.

---

## Background Jobs

All jobs inherit from `ApplicationJob` (ActiveJob). Queues are defined in `config/sidekiq.yml`.

| Job | Queue | Purpose |
|---|---|---|
| `BatchIngestJob` | `batch_ingest` | Processes S3-triggered manifest uploads |
| `BatchScanJob` | `batch_ingest` | Polls dropbox for new manifests |
| `MediaObjectIndexingJob` | `default` | Full Solr re-index of a MediaObject including child fields |
| `WaveformJob` | `default` | Generates audio waveform data for a MasterFile |
| `MigrateToS3Job` | `default` | Migrates master files to S3 |
| `ReindexJob` | `default` | Bulk Solr reindex |
| `UpdateDependentPermalinksJob` | `default` | Refreshes handle permalinks after publish |

- Always use `perform_later`. Never call `perform_now` from a controller.
- For rate-limiting use `activejob-traffic_control`. For deduplication use `activejob-uniqueness`.

---

## Routing Conventions

- Standard Rails RESTful routes for all resources.
- UMD-specific routes are annotated with `# UMD Customization` / `# End UMD Customization`.
- `Avalon::Routing::CanConstraint` gates admin-only routes (Sidekiq UI, AboutPage) via CanCan ability.
- JSON-only actions use `constraints: { format: 'json' }`.
- `media_objects` uses separate `put :update` constraints: HTML routes to `update`, JSON routes to `json_update`.

---

## Authorization

- Uses **CanCan** (`app/models/ability.rb`). Standard pattern: `load_and_authorize_resource` in controllers.
- `SecurityHelper` provides streaming authorization helpers used in controllers and views.
- **Before modifying `ability.rb`**, read `umd_docs/AvalonPermissions.md` - UMD's permission model diverges from stock Avalon (Published does not imply streamable).
- `AccessToken` provides a JWT-based authorization path that bypasses standard CanCan checks for stream/download.

---

## Frontend Conventions

### Two Asset Pipelines (coexist)

1. **Sprockets** (`app/assets/javascripts/`) - Legacy CoffeeScript and `.es6` files. Do not add new features here; prefer Shakapacker.
2. **Shakapacker** (`app/javascript/`) - Modern React/ES modules bundled by Webpack. Entry points in `packs/`. Rendered via `react_on_rails` `react_component` helper in ERB.

### React Components

- All components live in `app/javascript/components/`.
- UMD-specific components are prefixed with `Umd` (e.g., `UmdRestrictedPlayback.jsx`) or `UMD` (e.g., `UMDFacetFilter.jsx`).
- Props are passed from ERB: `<%= react_component('MyComponent', { prop: value }) %>`
- **Every new component must be registered** in both `app/javascript/packs/application.js` and `app/javascript/packs/server-bundle.js` via `ReactOnRails.register({ MyComponent })`.
- Use **functional components with hooks** (`useState`, `useRef`). Class components are legacy.
- **PropTypes validation is required** for all component props.
- Component-scoped styles go in a sibling `.scss` file (e.g., `Ramp.scss` alongside `MediaObjectRamp.jsx`).

---

## Docker & Local Development

The canonical local setup uses Docker Compose. The development hostname is `av-local` (not `localhost`).

**Prerequisite:** Add `127.0.0.1 av-local` to `/etc/hosts`.

```bash
cp env_template .env
# Edit .env - SAML_SP_PRIVATE_KEY and SAML_SP_CERTIFICATE are required
# Obtain from: kubectl -n test get secret avalon-common-env-secret

docker-compose pull --ignore-buildable
docker-compose build
docker-compose up avalon worker
# App available at http://av-local:3000
```

### Environment Variables

| Variable | Purpose |
|---|---|
| `SAML_SP_PRIVATE_KEY` | SAML SP private key **(required)** |
| `SAML_SP_CERTIFICATE` | SAML SP certificate **(required)** |
| `SAML_ISSUER` | Overrides SAML issuer (optional) |
| `IP_MANAGER_SERVER_URL` | UMD IP Manager API URL |
| `IP_MANAGER_TIMEOUT` | Timeout in seconds (default: 5) |
| `UMD_HANDLE_SERVER_URL` | Handle server REST API URL |
| `UMD_HANDLE_JWT_TOKEN` | JWT token for Handle server |
| `MATOMO_ANALYTICS_URL` | Matomo instance URL |
| `MATOMO_ANALYTICS_SITE_ID` | Matomo site ID |
| `MATOMO_ANALYTICS_CDN_SRC` | Matomo JS CDN URL |
| `SETTINGS__*` | Any `config` gem setting override |

### Docker Image Tagging Convention

```bash
# Dev:     docker.lib.umd.edu/avalon:latest
# RC:      docker.lib.umd.edu/avalon:8.1.1-umd-0-rc2
# Release: docker.lib.umd.edu/avalon:8.1.1-umd-0
# Hotfix:  docker.lib.umd.edu/avalon:8.1.1-umd-0.1
docker build -t IMAGE_TAG .
docker push IMAGE_TAG
```

On M-series Macs, build images in the Kubernetes cluster (not locally) to ensure the correct CPU architecture.

---

## Rake Tasks

```bash
# Create a user
rails avalon:user:create avalon_username=admin@example.com avalon_password=password avalon_groups=administrator

# Start services (non-Docker dev)
rake avalon:services:start && rake avalon:db_migrate

# Move dropbox files to archive (run dry run first)
dry_run=true rails umd:move_dropbox_files_to_archive
rails umd:move_dropbox_files_to_archive

# Create S3 dropbox buckets for existing collections
rails umd:ensure_collection_s3_bucket
```

---

## Common Patterns

### Adding a UMD-only route

```ruby
# config/routes.rb
# UMD Customization
resources :my_resource
# End UMD Customization
```

### Adding a UMD-only gem

```ruby
# Gemfile
# UMD Customization
gem 'some-gem'
# End UMD Customization
```

### Extending MediaObject Solr indexing

- Add fields to `to_solr` inside `# UMD Customization` markers.
- Fields that aggregate child (MasterFile) data go in `fill_in_solr_fields_that_need_sections`.
- Trigger background re-indexing with `MediaObjectIndexingJob.perform_later(id)`. Never call `to_solr(include_child_fields: true)` synchronously inside a request cycle.

### Creating a new service object

```ruby
# app/services/umd_my_service.rb
# frozen_string_literal: true

class UmdMyService
  def initialize
    @connection = Faraday.new(ENV['MY_SERVICE_URL']) do |conn|
      conn.response :json
      conn.adapter :net_http
      conn.options.timeout = ENV['MY_SERVICE_TIMEOUT']&.to_i || 5
      conn.options.open_timeout = ENV['MY_SERVICE_TIMEOUT']&.to_i || 5
    end
  end

  class APIError < StandardError; end
end
```

Add a spec at `spec/services/umd_my_service_spec.rb` using `webmock` to stub all HTTP calls.

### Creating a new React component

```jsx
// app/javascript/components/UmdMyFeature.jsx
import React from 'react';
import PropTypes from 'prop-types';

const UmdMyFeature = ({ title }) => {
  return <div>{title}</div>;
};

UmdMyFeature.propTypes = {
  title: PropTypes.string.isRequired,
};

export default UmdMyFeature;
```

Render from ERB: `<%= react_component('UmdMyFeature', { title: @media_object.title }) %>`

### Modifying access control

- Read `umd_docs/AvalonPermissions.md` first.
- Abilities are defined in `app/models/ability.rb`.
- `SecurityService` handles streaming URL signing (AWS CloudFront or token-based).
- `StreamToken` is used for non-AWS streaming; `Aws::CF::Signer` is used for AWS CloudFront.

---

## Known Quirks & Gotchas

1. **Devise + SAML wrapper** - The `Rails.application.reloader.to_prepare` block in `config/initializers/devise.rb` is deliberately commented out due to a Devise/OmniAuth-SAML incompatibility. Do not restore it. See "Configuration Oddities" in `UMD-README.md`.

2. **Firefox in local dev** - Login fails in Firefox because the `av-local` hostname causes the `SameSite=None` session cookie to be rejected without the `Secure` flag. Use Chrome for local development.

3. **`psych` pinned below 4** - Required for Ruby 3.x YAML compatibility. Do not upgrade.

4. **`sass` replaced by `sassc-rails`** - The old `gem 'sass', '3.4.22'` pin is gone; the app now uses `sassc-rails`. Do not add back the standalone `sass` gem.

5. **`section_list` migration guard** - `MediaObject#section_ids` lazy-migrates from `ordered_master_file_ids` to a JSON-stored `section_list`. Do not remove the `self.section_list.nil?` guard.

6. **`around_create` double-save on MediaObject** - A second save is performed after create to sync `master_file_ids` with `section_ids`. This is intentional; do not remove it.

7. **`om` gem from custom fork** - Uses `avalonmediasystem/om` tagged `v3.2.0-ruby3`. Do not replace with the canonical `om` gem from RubyGems.

8. **`browse-everything` gem from branch** - Uses the `v1.2-avalon` branch of `avalonmediasystem/browse-everything`. Do not replace with the canonical gem.

9. **CI is disabled** - `Jenkinsfile` is renamed `Jenkinsfile.disabled` and GitHub webhooks to Jenkins are disabled. Run tests manually before opening a PR.

10. **Solr configset name** - The Solr configset is named `avalon`. Collection admin is managed by `SolrCollectionAdmin` and `SolrCollectionCreator` service objects.

11. **`<%# %>` ERB comments inside `<%= %>` expressions** - ERB comment tags (`<%# UMD Customization %>`) cannot be nested inside `<%= ... %>` expressions (e.g., inside a hash passed to `react_component`). They break out of the enclosing expression and cause a Ruby syntax error. Use plain Ruby `# UMD Customization` comments instead when inside an expression.

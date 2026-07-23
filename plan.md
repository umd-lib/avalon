## Plan: Avalon Transcription POC Architecture

Recommended approach: implement a section-level transcription pipeline that mirrors Avalon encoding patterns, with a provider interface defined up front and AWS Transcribe as the first fully implemented adapter. Keep the architecture provider-ready now, but avoid feature-heavy parity work for a second provider until Phase 3. This gives fastest validation while preserving a clean expansion path.

**Steps**
1. Phase A: Domain and lifecycle foundation
2. Phase B: Provider orchestration and background processing
3. Phase C: Admin UX (enqueue and dashboard)
4. Phase D: Output materialization and Avalon association
5. Phase E: Hardening, observability, and rollout checks

Phase A details:
1. Define one transcription request as one MasterFile-targeted job record; add optional MediaObject action that enqueues all eligible sections by creating one job per section.
2. Add TranscriptionRequest persistence with explicit status lifecycle. Note: `ActiveEncode::EncodeRecord` has no DB-level unique/active constraint to mirror — its duplicate-submission guard is a simple app-level presence check (`master_file.workflow_id.present?` in `active_encode_jobs.rb`). Design TranscriptionRequest's duplicate guard fresh; consider a real DB constraint (e.g. partial unique index on master_file_id where status is active) since this is a new model, not something being cloned from precedent.
3. Add authorization capability for admin dashboard and enqueue actions, following encode dashboard style.

Phase B details:
1. Add dedicated transcription queue and job classes:
   - enqueue/submit job (provider submission)
   - polling status job (scheduled)
   - completion materialization job (download/normalize/create SupplementalFile)
   - cancel job
2. Add provider interface and registry first, then implement AWS adapter fully and AssemblyAI adapter to same contract.
3. Use sidekiq-cron based polling sweep over running/submitted jobs grouped by provider.

Phase C details:
1. Add admin-only action buttons on MediaObject item view:
   - per-section button (primary)
   - all-sections button (optional bulk convenience)
2. Button visibility rules:
   - show only if no existing caption/transcript for target section
   - no active transcription job exists for that section
   - user is admin
3. Add transcription dashboard page and JSON data endpoints reusing encoding dashboard interaction pattern.
4. Add actions from dashboard: retry, cancel, details.

Phase D details:
1. Store provider raw response JSON in TranscriptionRequest columns for audit/debug.
2. Store normalized transcript text in TranscriptionRequest for search/index preparation and diagnostics.
3. Create SupplementalFile artifacts on completion:
   - caption artifact: .vtt with `tags` array including `caption` and `machine_generated`
   - transcript artifact: .txt or .vtt with `tags` array including `transcript` and `machine_generated`
   - Note: `machine_generated` is a value within the existing serialized `tags` array column (validated by an `array_inclusion`-style allow-list), not a separate boolean/marker column. No schema change needed here — just include the tag value, which is already in SupplementalFile's allowed tag list.
4. Attach SupplementalFile to MasterFile (parent_id = master_file_id) and trigger reindex pattern used by SupplementalFile callbacks and media object indexing.

Phase E details:
1. Add structured logging with consistent prefix and correlation keys (transcription_job_id, provider_job_id, master_file_id, media_object_id).
2. Add retry policy by failure class (network/transient vs permanent/media invalid).
3. Add least-privilege IAM guidance and config validation on boot.
4. Add feature flag / settings toggle for provider enablement and optional AssemblyAI enablement.

**Relevant files**
- /Users/mohideen/git/avalon/app/controllers/encode_records_controller.rb — dashboard/index/paged JSON/progress endpoint pattern to clone for transcription dashboard.
- /Users/mohideen/git/avalon/app/views/encode_records/index.html.erb — dashboard view composition pattern with React table props.
- /Users/mohideen/git/avalon/app/models/ability.rb — encode dashboard admin permission pattern to mirror for transcription permissions.
- /Users/mohideen/git/avalon/config/routes.rb — routing style for dashboard collection actions and nested resource actions.
- /Users/mohideen/git/avalon/app/jobs/active_encode_jobs.rb — submit/cancel job shape and guard checks for duplicate work.
- /Users/mohideen/git/avalon/config/sidekiq.yml — dedicated queue naming and weighting convention.
- /Users/mohideen/git/avalon/config/initializers/sidekiq.rb — sidekiq-cron scheduling pattern for polling sweep.
- /Users/mohideen/git/avalon/app/models/supplemental_file.rb — caption/transcript tagging via serialized `tags` array (with `machine_generated` as one allowed tag value, not a separate column), storage/index callback behavior.
- /Users/mohideen/git/avalon/app/models/concerns/supplemental_file_read_behavior.rb — association retrieval behavior for caption/transcript presence checks.
- /Users/mohideen/git/avalon/app/views/media_objects/_file_upload.html.erb — admin edit-form "Section files" tab; has existing per-master-file action-button row (Delete/Move/Download/Edit) to mirror for a Transcribe button, and already renders `_supplemental_files_upload` partials per section for caption/transcript tags. (Note: `_item_view.html.erb` is the public viewer/playback page, not an admin surface — not a fit for admin controls.)
- /Users/mohideen/git/avalon/app/views/media_objects/_supplemental_files_upload.html.erb — already queries `ActiveEncode::EncodeRecord.find_by(master_file_id: ...)` to show caption counts per section; good integration point for surfacing transcription job status alongside existing caption/transcript uploads.

**Verification**
1. Model/state tests: lifecycle transitions, active-duplicate prevention, cancel/retry behavior.
2. Job tests: submit, poll, completion materialization, cancel, idempotent re-runs.
3. Provider contract tests: shared examples run against AWS and AssemblyAI adapters.
4. Controller/ability tests: admin-only access to enqueue and dashboard endpoints.
5. Feature test: admin enqueues section job, dashboard shows progression, completion creates SupplementalFile artifacts, button disappears afterwards.
6. Failure-path tests: provider timeout, unsupported media, malformed provider output, cancellation during polling.

**Decisions**
- Scope unit: one job per MasterFile section, with optional MediaObject bulk action that fans out to section jobs.
- Canonical success artifact: WebVTT caption SupplementalFile; also create transcript artifact when provider output supports it without meaningful extra complexity/cost.
- Language strategy: default from media metadata/config and allow admin override at enqueue.
- Status updates: sidekiq-cron polling for POC.
- Provider strategy recommendation: abstraction first (minimal interface) + AWS complete first, then AssemblyAI full adapter in follow-on phase.

**Further Considerations**
1. Decide whether admin-only should remain strict administrator or include managers/editors for enqueue rights in later phases.
2. Decide whether transcript text artifact should be plain text or VTT-as-transcript for consistency with current parser/search behavior.
3. Decide if bulk all-sections action should skip ineligible sections silently or return per-section eligibility feedback in UI.

# AWS Transcribe Setup for the Transcription POC

This covers the configuration and least-privilege IAM policy needed to run
the `aws_transcribe` transcription provider (`TranscriptionProviders::AwsTranscribe`).
See `plan.md` for the overall feature design.

## Configuration

The feature is off by default. In `config/settings.yml` (or environment
overrides):

```yaml
transcription:
  enabled: true
  default_provider: aws_transcribe
  aws:
    output_bucket: your-transcribe-output-bucket
    # Optional: segment Transcribe's output under a prefix instead of the
    # bucket root — see "Sharing a bucket with other content" below.
    output_prefix:
    # Prefix for Transcribe job and vocabulary names — see "Scoping IAM per
    # environment" below.
    job_name_prefix: avalon
    # Optional: label distinct speakers — see "Speaker diarization" below.
    diarization:
      enabled: false
      max_speakers: 10
```

or via environment variables:

```
SETTINGS__TRANSCRIPTION__ENABLED=true
SETTINGS__TRANSCRIPTION__AWS__OUTPUT_BUCKET=your-transcribe-output-bucket
SETTINGS__TRANSCRIPTION__AWS__JOB_NAME_PREFIX=avalon-sandbox
SETTINGS__TRANSCRIPTION__AWS__DIARIZATION__ENABLED=true
```

`config/initializers/transcription.rb` validates this on boot — the app will
refuse to start if `enabled: true` is set with an unknown provider, or with
`aws_transcribe` selected but no `output_bucket` configured.

Only MasterFiles whose resolved media source is already in S3 can be
transcribed (see `MasterFile#input_path` / `FileLocator`). A local-filesystem
source raises `TranscriptionProviders::UnsupportedMediaSource` when submitted.

## Required IAM permissions

The IAM role/user Avalon uses for AWS API calls needs:

1. **Transcribe job lifecycle**, scoped to jobs this app creates (job names
   are `<job_name_prefix>-<master_file_id>-<random>`, default prefix
   `avalon`, see `AwsTranscribe#job_name_for`):

   ```json
   {
     "Effect": "Allow",
     "Action": [
       "transcribe:StartTranscriptionJob",
       "transcribe:GetTranscriptionJob",
       "transcribe:DeleteTranscriptionJob"
     ],
     "Resource": "arn:aws:transcribe:<region>:*:transcription-job/avalon-*"
   }
   ```

   Note that account-id is intentionally left as `*` here rather than a
   specific account — see "Scoping IAM per environment" below for why that's
   inert in practice and region is the field actually worth pinning.

2. **Read the source media** from wherever Avalon's master files live in S3:

   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:GetObject"],
     "Resource": "arn:aws:s3:::<masterfiles-bucket>/*"
   }
   ```

3. **Read and write the Transcribe output bucket**
   (`Settings.transcription.aws.output_bucket`). Transcribe writes the
   transcript JSON and VTT subtitle file here; the app reads them back via
   `Aws::S3::Client#get_object` (see "Why the app needs s3:GetObject on the
   output bucket" below) — it does not fetch them via an unauthenticated
   HTTP request, so bucket-level public read is neither required nor
   recommended:

   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:GetObject", "s3:PutObject"],
     "Resource": "arn:aws:s3:::<output-bucket>/*"
   }
   ```

   If `output_prefix` is set, scope this down to just that prefix instead
   of the whole bucket (see "Sharing a bucket with other content" below):

   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:GetObject", "s3:PutObject"],
     "Resource": "arn:aws:s3:::<output-bucket>/<output_prefix>/*"
   }
   ```

4. **Custom vocabulary lifecycle**, scoped to vocabularies this app creates
   (names are `<job_name_prefix>-vocab-<collection_id>`, see
   `TranscriptionVocabulary#set_aws_vocabulary_name`) — see "Custom
   vocabulary" below:

   ```json
   {
     "Effect": "Allow",
     "Action": [
       "transcribe:CreateVocabulary",
       "transcribe:UpdateVocabulary",
       "transcribe:GetVocabulary",
       "transcribe:DeleteVocabulary",
       "transcribe:StartTranscriptionJob"
     ],
     "Resource": "arn:aws:transcribe:<region>:*:vocabulary/avalon-vocab-*"
   }
   ```

   `transcribe:StartTranscriptionJob` has to be granted on the vocabulary
   resource too, not just the transcription-job resource in permission 1
   above — when a job's `Settings.VocabularyName` references a vocabulary,
   AWS IAM checks that action against *both* ARNs. Omitting it here produces
   an `AccessDeniedException` naming the vocabulary ARN even though the
   transcription-job permissions are already correct.

Do not grant broader `transcribe:*` or account-wide `s3:*` — the above is
sufficient for this adapter's full lifecycle (submit, poll, fetch, cancel,
plus managing custom vocabularies).

### Why the app needs s3:GetObject on the output bucket

When `StartTranscriptionJob` is called with a customer-owned
`OutputBucketName` (as this adapter always does), AWS Transcribe returns
plain `https://s3.<region>.amazonaws.com/<bucket>/<key>` links in
`TranscriptFileUri` / `SubtitleFileUris` — these are **not** pre-signed
URLs (unlike the default AWS-managed output location, which does return
temporary pre-signed URLs). Fetching them requires the caller's own
SigV4-signed request, which is why `AwsTranscribe#fetch_transcript` uses an
`Aws::S3::Client` rather than a raw HTTP GET.

### Sharing a bucket with other content

`output_bucket` doesn't have to be dedicated to Transcribe — for example,
you might reuse the bucket already configured for `SupplementalFile`
storage (`config/storage.yml`'s `amazon`/`generic_s3` services, driven by
`SETTINGS__ACTIVE_STORAGE__BUCKET`). If you do, set `output_prefix` (e.g.
`transcribe-output`) so Transcribe's job output lands under
`<output_prefix>/<job-name>.json` / `.vtt` instead of the bucket root,
keeping it clearly separated from ActiveStorage's own key layout for
SupplementalFile attachments. A trailing slash is added automatically if
you omit one. Leaving `output_prefix` blank writes to the bucket root,
matching the adapter's original (pre-prefix) behavior — existing
deployments don't need to set anything to keep working as before.

### Speaker diarization

Off by default. When `diarization.enabled` is true, jobs are submitted with
AWS Transcribe's `ShowSpeakerLabels`/`MaxSpeakerLabels` settings, so the
transcript JSON and the VTT Transcribe generates both include speaker
labels — `max_speakers` is a required upper bound AWS uses when enabled (an
estimate, not an exact count), not a hard cap. This only affects the VTT
caption artifact; the plain-text `transcript.txt` `SupplementalFile` still
has no speaker labels either way, since `AwsTranscribe#extract_transcript_text`
just pulls the flat `results.transcripts[0].transcript` string — adding
speaker labels there would mean parsing the response's separate
`speaker_labels` segment data, which isn't implemented.

Both `enabled` and `max_speakers` can be overridden per `Admin::Collection`
(`#diarization_enabled?`/`#diarization_max_speakers`, set from the
collection's edit page) — an unset collection value falls back to this
global default.

### Custom vocabulary

Off by default, and managed entirely per `Admin::Collection` — there is no
site-wide default (unlike diarization). AWS Transcribe's Custom Vocabulary
feature biases recognition toward specific words/phrases — useful for
proper nouns and domain jargon that a general-purpose language model gets
wrong (e.g. an internal application name being misheard as something else
entirely).

Unlike the original reference-only design, **Avalon now creates and manages
vocabulary content itself**: an admin pastes a word/phrase list (one per
line) into the "Custom Vocabulary" field on a collection's edit page, and
Avalon handles the rest via `TranscriptionVocabulary` (one row per
collection) and `TranscriptionProviders::AwsTranscribeVocabulary`:

1. Saving a non-blank list creates or updates a `TranscriptionVocabulary`
   record (`state: pending`) and enqueues `TranscriptionVocabularyJobs::SyncVocabularyJob`,
   which calls AWS's `CreateVocabulary` (first sync) or `UpdateVocabulary`
   (subsequent edits) with the phrase list as `Phrases`. AWS vocabulary
   names can't be renamed, so the same deterministic name
   (`<job_name_prefix>-vocab-<collection_id>`) is reused for the life of
   the collection's vocabulary.
2. `TranscriptionVocabularyJobs::PollVocabulariesJob` (sidekiq-cron, every
   1 min) sweeps `pending` records via `GetVocabulary` until AWS reports
   `READY` or `FAILED` (with a `FailureReason` surfaced as `error_message`).
3. `AwsTranscribe#job_settings` only applies a vocabulary to a
   transcription job once it's `READY` **and** its language matches the
   job's resolved language — a custom vocabulary requires an explicit AWS
   `LanguageCode`, so a job that falls back to automatic language
   identification (no entry in `LANGUAGE_CODE_MAP` for the item's
   language) never gets one.
4. Saving a blank list enqueues `TranscriptionVocabularyJobs::DeleteVocabularyJob`,
   which best-effort deletes the AWS-side vocabulary (`DeleteVocabulary`)
   and always removes the local record regardless of whether that call
   succeeded.

Only a simple phrase list is supported (AWS's `Phrases` parameter) — no
`SoundsLike`/`IPA` pronunciation hints or `DisplayAs` casing, which AWS only
accepts via a file uploaded to S3 (`VocabularyFileUri`) instead of inline
`Phrases`.

### Scoping IAM per environment

If multiple environments (e.g. sandbox/test/qa) share one AWS account and
each gets its own IRSA role, set a distinct `job_name_prefix` per
environment (e.g. `avalon-sandbox`, `avalon-test`, `avalon-qa`) and match
each role's Transcribe policy `Resource` patterns to it
(`transcription-job/avalon-sandbox-*`, `vocabulary/avalon-sandbox-vocab-*`,
etc.). This is defense-in-depth, not
the primary isolation boundary — that's the IRSA role's OIDC trust
condition (e.g. `oidc_subjects_with_wildcards = ["system:serviceaccount:sandbox:avalon"]`),
which already prevents one environment's pods from assuming another
environment's role at all, regardless of job naming. Without a per-environment
prefix, all environments' jobs share the plain `avalon-*` pattern, which is
fine as long as each environment's role isn't otherwise compromised (and even
then, doesn't grant `transcribe:ListTranscriptionJobs`, so a compromised role
still can't enumerate another environment's job names to act on them — only
guess ones it already knows). The main non-security reason to set it anyway:
without it, jobs from every environment show up under the same `avalon-*`
prefix in the AWS Console/CLI with no way to tell which environment created
which one.

An IAM policy `Resource` ARN's account-id and region fields are worth
distinguishing when scoping this: leaving account-id as `*` costs nothing,
since IRSA credentials only ever belong to one account and Transcribe has no
resource-based (cross-account sharing) policies — a wildcard there can never
actually reach another account's resources. Region is different: IAM roles
aren't region-scoped, so pinning `${data.aws_region.current.name}` instead of
`*` for region is a real (if narrow) reduction in blast radius, not just
cosmetic precision.

## Retry/failure behavior

`TranscriptionJobs::TRANSIENT_ERRORS` (network errors, Transcribe
`InternalFailureException`/`LimitExceededException`) are retried
automatically by ActiveJob with exponential backoff (5 attempts) before the
request is marked `failed`. Anything else — bad input, unknown provider,
an unsupported (non-S3) media source, AWS `AccessDenied`, etc. — fails the
`TranscriptionRequest` immediately, since retrying won't change the outcome.
If jobs are failing immediately with an access error, check the IAM policy
above before assuming it's a code bug.

`TranscriptionVocabularyJobs::TRANSIENT_ERRORS` (same error set) governs
`SyncVocabularyJob` the same way; a permanent failure marks the
`TranscriptionVocabulary` `failed` with `error_message` set. `PollVocabulariesJob`
and `DeleteVocabularyJob` don't retry — the cron sweep re-runs every minute
regardless, and deletion is already best-effort by design.

## Human review workflow

Off by default, and set **per `Admin::Collection`**
(`Admin::Collection#review_required?`, set from the collection's edit page —
same override-with-fallback pattern as diarization and custom vocabulary; an
unset collection value falls back to `Settings.transcription.review.enabled`).
When enabled for a collection, machine-generated captions/transcripts don't
go live immediately — they're gated behind administrator approval.

- `TranscriptionJobs::CompleteTranscriptionRequestJob` creates **one**
  `SupplementalFile` per completed request — a WebVTT file tagged both
  `caption` and `transcript` (the same "treat as transcript" pattern the
  Section Files upload UI already supports for manual uploads,
  `SupplementalFile#caption_transcript?`), not two independent artifacts.
  The plain-text transcript view is derived from that single file's cues on
  demand (`Avalon::TranscriptParser`, already used for Solr indexing) rather
  than stored separately, so there's only ever one file for a reviewer to
  check and correct, and no risk of the caption and transcript drifting out
  of sync with each other. (Falls back to a transcript-only `.txt` artifact
  — no `caption` tag — on the rare provider response with no VTT, e.g. a
  language AWS doesn't generate subtitles for.) It's also tagged `private`
  and given `review_status: 'pending_review'` only when the owning
  collection has `review_required?` true; otherwise it behaves exactly as
  before — immediately visible, no review state.
- Admins review pending items at `/transcription_reviews`, a dashboard
  listing every `pending_review` file across all collections (mirrors the
  `/transcription_requests` dashboard's `paged_index` pattern) — one row per
  section awaiting review. Each row links to the owning
  `MasterFile`/`MediaObject` and offers four actions:
  - **Edit** (`GET`/`POST` `/transcription_reviews/:id/edit` and
    `/update_text`) — a lightweight in-place editor
    (`Avalon::WebvttCueEditor`, `lib/avalon/webvtt_cue_editor.rb`) for
    correcting the *text* of individual cues (e.g. a mistranscribed word),
    leaving timestamps/cue structure untouched. Saves back into the same
    `SupplementalFile` record — same id/tags/`review_status`, not a
    destroy+recreate. Only available for `pending_review` files that carry
    the `caption` tag (`SupplementalFile#editable_transcription_review?`) —
    the rare transcript-only `.txt` fallback artifact (no VTT at all, see
    below) has no Edit link. Deliberately narrow, not a general captions
    authoring tool: no way to add/remove cues or change timing.
  - **Approve** (`SupplementalFile#approve!`) — removes the `private` tag,
    making it publicly visible, and re-indexes the parent `MediaObject`.
  - **Reject** (`SupplementalFile#reject!`) — stays hidden permanently, but
    the record is kept (not destroyed) for audit purposes. A rejected
    caption/transcript no longer blocks resubmitting transcription for that
    section (`TranscriptionRequestsController#enqueue_if_eligible` excludes
    `rejected` files from its "already has one" check) — a `pending_review`
    or `approved` one still does.
  - **Replace** — links out to the item's existing Section Files upload
    step (`edit_media_object_path(media_object_id, step: 'file-upload')`)
    to upload a corrected file through the normal upload flow — the right
    choice for structural corrections (re-timing, adding/removing cues, or
    a fundamentally wrong transcript) that the narrower in-place Edit
    action doesn't support.
- `pending_review → approved` and `pending_review → rejected` are the only
  transitions; `SupplementalFile#approve!`/`#reject!` raise
  `SupplementalFile::InvalidReviewTransition` if called on a file that isn't
  currently `pending_review` (e.g. reviewing the same item twice).
- The owning `TranscriptionRequest` tracks this too, so its status on
  `/transcription_requests` doesn't misleadingly read `completed` while the
  output is still sitting in review: `CompleteTranscriptionRequestJob`
  transitions it to `in_review` (instead of `completed`) whenever the
  artifact it created is `pending_review`, and `TranscriptionReviewsController#approve`/`#reject`
  move it on to `completed`/`rejected` once a reviewer acts (matched to the
  `SupplementalFile` via `master_file_id` — there's no direct FK, since a
  `MasterFile` can only have one `in_review` request at a time). `in_review`
  is excluded from both `ACTIVE_STATUSES` (so `PollTranscriptionRequestsJob`
  doesn't keep re-fetching an already-finished provider job and re-trigger
  completion materialization) and `TERMINAL_STATUSES` (a human still needs
  to act) — see `TranscriptionRequest::TRANSITIONS`.
- Reviewing is gated by a dedicated `:transcription_review` CanCan ability
  (administrators only currently — see `Ability#transcription_review_permissions`),
  kept separate from `:manage, TranscriptionRequest` so it can be broadened
  to collection managers later without touching transcription-dashboard access.

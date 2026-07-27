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
       "transcribe:DeleteVocabulary"
     ],
     "Resource": "arn:aws:transcribe:<region>:*:vocabulary/avalon-vocab-*"
   }
   ```

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

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
    # Prefix for Transcribe job names — see "Scoping IAM per environment" below.
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

Do not grant broader `transcribe:*` or account-wide `s3:*` — the above is
sufficient for this adapter's full lifecycle (submit, poll, fetch, cancel).

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

### Scoping IAM per environment

If multiple environments (e.g. sandbox/test/qa) share one AWS account and
each gets its own IRSA role, set a distinct `job_name_prefix` per
environment (e.g. `avalon-sandbox`, `avalon-test`, `avalon-qa`) and match
each role's Transcribe policy `Resource` pattern to it
(`transcription-job/avalon-sandbox-*`, etc.). This is defense-in-depth, not
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

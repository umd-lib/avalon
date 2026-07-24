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
```

or via environment variables:

```
SETTINGS__TRANSCRIPTION__ENABLED=true
SETTINGS__TRANSCRIPTION__AWS__OUTPUT_BUCKET=your-transcribe-output-bucket
```

`config/initializers/transcription.rb` validates this on boot — the app will
refuse to start if `enabled: true` is set with an unknown provider, or with
`aws_transcribe` selected but no `output_bucket` configured.

Only MasterFiles whose resolved media source is already in S3 can be
transcribed (see `MasterFile#input_path` / `FileLocator`). A local-filesystem
source raises `TranscriptionProviders::UnsupportedMediaSource` when submitted.

## Required IAM permissions

The IAM role/user Avalon uses for AWS API calls needs:

1. **Transcribe job lifecycle**, scoped to jobs this app creates (all job
   names are prefixed `avalon-`, see `AwsTranscribe#job_name_for`):

   ```json
   {
     "Effect": "Allow",
     "Action": [
       "transcribe:StartTranscriptionJob",
       "transcribe:GetTranscriptionJob",
       "transcribe:DeleteTranscriptionJob"
     ],
     "Resource": "arn:aws:transcribe:<region>:<account-id>:transcription-job/avalon-*"
   }
   ```

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

## Retry/failure behavior

`TranscriptionJobs::TRANSIENT_ERRORS` (network errors, Transcribe
`InternalFailureException`/`LimitExceededException`) are retried
automatically by ActiveJob with exponential backoff (5 attempts) before the
request is marked `failed`. Anything else — bad input, unknown provider,
an unsupported (non-S3) media source, AWS `AccessDenied`, etc. — fails the
`TranscriptionRequest` immediately, since retrying won't change the outcome.
If jobs are failing immediately with an access error, check the IAM policy
above before assuming it's a code bug.

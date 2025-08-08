# Avalon

## UMD documentation

UMD-generated documentation for Avalon should be placed in the
"[umd_docs](umd_docs/)" subdirectory.

* [UMD Customizations](umd_docs/UmdCustomizations.md)
  * [Avalon Permissions](umd_docs/AvalonPermissions.md)
  * [umd-handle Integration](umd_docs/UmdHandleIntegration.md)

## Development Setup

Instructions for building and running Avalon locally can be found in
[umd_docs/DockerDevelopmentEnvironment.md](umd_docs/DockerDevelopmentEnvironment.md)

## Jenkinsfile.disabled

The "Jenkinsfile" for this project is currently disabled because the tests
take an extremely long time to run (6+ hours), and consume enough resources
to hamper the operation of the CI servers.

Once these issues are corrected, renaming the file back to "Jenkinsfile" will
restore the continuous integration builds.

The "Webhooks" in the <https://github.com/umd-lib/avalon> that notify Jenkins of
pull requests and branch updates have also been disabled. These should be
re-enabled when restoring the continuous integration builds.

## SAML Environment Specific Configuration

The following variables were added to facilitate configuring environment
specific SAML configuration. These environment variables will take
precedence over the configuration in the [settings.yml](./config/settings.yml).

* `SAML_ISSUER`: Overrides the `issuer` configuration.
* `SAML_SP_PRIVATE_KEY`: Overrides the `private_key` configuration.
* `SAML_SP_CERTIFICATE`: Overrides the `certificate` configuration.

## Matomo Analytics

The UMD instance of Avalon uses Matomo Analytics (<https://matomo.org/>) for
tracking user activity.

Matomo tracking is enabled when all of the following environment variables are
configured with the appropriate values, which can be obtained from the
"Digital Collection - Audiovisual (Avalon)" website configuration on the UMD
Matomo dashboard:

* MATOMO_ANALYTICS_URL - URL of the UMD Matomo website
* MATOMO_ANALYTICS_SITE_ID - The Matomo-provided site id
* MATOMO_ANALYTICS_CDN_SRC - CDN URL to the UMD Matomo JavaScript script

If any of the values are not provided, Matomo tracking will be disabled.

## Docker Build for K8s Deployment

The k8s-avalon stack uses the avalon image built from this repository.

**Note:** On M-series MacBooks, the Docker images should be built in the
Kubernetes cluster to ensure that they have the correct architecture. See
<https://github.com/umd-lib/k8s/blob/main/docs/DockerBuilds.md>.

1. Build and tag the image

    ```zsh
    # Substitute IMAGE_TAG with appropriate value
    # Example IMAGE_TAG values for different scenarios:
    #    Dev Build: docker.lib.umd.edu/avalon:latest
    #    RC Build: docker.lib.umd.edu/avalon:7.1-umd-0-rc2
    #    Release Build: docker.lib.umd.edu/avalon:7.1-umd-0
    #    Hotfix Build: docker.lib.umd.edu/avalon:7.1-umd-0.1
    docker build -t IMAGE_TAG .
    ```

2. Push it to UMD Nexus

    ```zsh
    # Substitute IMAGE_TAG with appropriate value
    docker push IMAGE_TAG
    ```

## Rails Tasks

### umd:move_dropbox_files_to_archive

Rails task for moving asset files from the dropbox directory to the archive
directory.

In LIBAVALON-196, the Avalon configuration (in "config/settings.yml") was
modified to automatically move ingested asset files from the dropbox directory
to a more protected "archive" directory. This change, however, did not move
existing asset files into the archive.

This Rails task examines all the MasterFile entries for asset files remaining
in the dropbox, and moves them to the "archive" directory specified in the
"master_file_management.move" parameter of the "config/settings.yml" file. The
MasterFile entries in the database will be updated with the new file location.

It is recommended that a "dry run" for the task be performed first. This will
identify the number of files that need to be moved, as well as any files that
are missing.

To perform a "dry run", use a "dry_run" environment variable (lower-case,
because lower-case is used in supplying arguments to other Avalon Rake tasks):

```zsh
dry_run=true rails umd:move_dropbox_files_to_archive
```

To perform the actual migration:

```zsh
rails umd:move_dropbox_files_to_archive
```

The console output will indicate any errors such as failed migrations
and failed deletions.

This Rails task is intended to be idempotent -- running the task multiple times
should be safe, as once a file has been moved to the archive, it is no longer
affected by this task.

## Configuration Oddities

### config/initializers/devise.rb

In Avalon 7.6, the configuration code in "config/initializers/devise.rb" was
wrapped in a "Rails.application.reloader.to_prepare" block, presumably to
silence a warning related to Devise autoloaded constants, see:

* <https://github.com/avalonmediasystem/avalon/commit/3f8a3bb8dff35c0b6936d70f0e99ddd35d15e03f>

However, there is a known Devise issue, where this wrapper interferes
with the configuration of Devise, see:

* <https://github.com/heartcombo/devise/issues/5699>

As of June 2025, the "Devise" fix indicated in the above issue has not been
incorporated into any Devise version. To workaround this issue, simply commented
out the wrapper.

Also, In the "Troubleshooting" section of the "Devise" gem, there is a
'"Request phase initiated" doesn't trigger' section:

<https://github.com/heartcombo/devise/wiki/OmniAuth:-Overview#request-phase-initiated-doesnt-trigger>

that suggests that the Devise configuration should *not* be placed within a
"Rails.application.reloader.to_prepare" wrapper.

A similar situation is described in detail in

<https://github.com/fxn/zeitwerk/issues/143>

but it is not clear if the proposed solutions apply here, because it is
discussion a custom strategy, not a strategy encapsulated in a Ruby gem.

One way to test if the customization in "config/initializers/devise.rb" can be
removed is to run:

```zsh
$ bin/rails middleware
```

in the Avalon Docker container. The resulting list should include:

```text
use OmniAuth::Strategies::SAML
```

If it does not, the customization is still needed.

**Note**: It is possible the "Rails.application.reloader.to_prepare" wrapper is
not needed. because running `bin/rails zeitwerk:check` (as suggested in
<https://guides.rubyonrails.org/v7.0/autoloading_and_reloading_constants.html#manual-testing>
to find Zeitwerk issues), does not report any issues related to Devise when
the wrapper is commented out.

### Session Cookie, Login, and Local Development

Avalon uses a "session" cookie ("_session_id") to control logins. Without
this cookie, the Devise authentication process falls into an infinite redirect
loop between the "/users/auth/saml" and "/users/sign_in" endpoints.

The UMD CAS web application firewall rejects any HTTP request with a
“service” HTTP parameter of “localhost” or “127.0.0.1”. Because of this,
UMD has customized Avalon to use "av-local" (instead of "localhost") for the
hostname in the local development environment.

The combination of the need for the session cookie, and the use of the
"av-local" hostname causes local development logins to fail when using the
Firefox web browser. This is because Firefox is rejecting the session cookie
with the following error in the browser console:

> Cookie “_session_id” rejected because it has the “SameSite=None” attribute
> but is missing the “secure” attribute.

The session cookie is configured by the "config/initializers/session_store.rb"
file. In a stock Avalon, the "SameSite" attribute of the cookie is never set,
and the "Secure" flag is only set for production environments (and when the
HTTP protocol is "https").

As documented by [MDN][mdn-browser-compatibility], when the "SameSite" attribute
is not set, Firefox defaults the attribute to "None", while Chrome defaults the
attribute to "Lax".

Setting the "SameSite" attribute to "None" requires the "Secure" flag, but this
usually isn't an issue for local development, because browsers do not enforce
this requirement when the hostname is "localhost". However, because UMD has
customized Avalon to use the "av-local" hostname, this requirement *is*
enforced, the cookie is rejected, and the infinite redirect loop occurs.

This is not an issue for Chrome, because it defaults the "SameSite" attribute
to "Lax".

To restore the ability to login with Firefox in the local development
environment, the session cookie configuration in
"config/initializers/session_store.rb" was modified to set the "SameSite"
attribute to "Lax" when the application is run in Rails "development" mode.

**Note:** After logging in a browser warning will be displayed (in both Firefox
and Chrome - the wording below is from Firefox):

> The information you have entered on this page will be sent over an insecure
> connection and could be read by a third party.

This is expected, and pre-existed this customization.

---
[mdn-browser-compatibility]: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie#browser_compatibility

# Avalon

## UMD documentation

UMD-generated documentation for Avalon should be placed in the
"[umd_docs](umd_docs/)" subdirectory.

* [Avalon Permissons](umd_docs/AvalonPermissions.md)
* [umd-handle Integration](umd_docs/UmdHandleIntegration.md)

## Development Setup

Instructions for building and running Avalon locally can be found in
[umd_docs/DockerDevelopmentEnvironment.md](umd_docs/DockerDevelopmentEnvironment.md)

## SAML Environment Specific Configuration

The following variables were added to facilate configuring environment
specific SAML configuration. These environment varaibles will take
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
    # Example IMAGE_TAG values for differnt scenarios:
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

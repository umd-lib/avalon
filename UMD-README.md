# Avalon

## UMD documentation

UMD-generated documentation for Avalon should be placed in the
"[umd_docs](umd_docs/)" subdirectory.

* [Avalon Permissons](umd_docs/AvalonPermissions.md)

## Development Setup

### Prerequisites

1) Edit the "/etc/hosts" file and add

```text
127.0.0.1 av-local
```

### Setup Instructions

The following instructions include steps marked **(M-series)** which are
required when setting up and running Avalon on M-series (Apple Silicon)
MacBooks. These steps can be ignored when running on other platforms.

1) Checkout the application and swtich to the directory:

    ```zsh
    git clone git@github.com:umd-lib/avalon.git
    cd avalon
    ```

2) Copy the "env_template" file to ".env":

    ``` zsh
    cp env_template .env
    ```

3) Edit the '.env" file:

    ```zsh
    vi .env
    ```

4) (Required) Determine the values for the "SAML_SP_PRIVATE_KEY" and
    "SAML_SP_CERTIFICATE" variables:

    ```zsh
    kubectl -n test get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_PRIVATE_KEY}' | base64 --decode
    kubectl -n test get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_CERTIFICATE}' | base64 --decode
    ```

    and set the parameters in the .env file:

    | Parameter              | Value                                |
    | ---------------------- | ------------------------------------ |
    | SAML_SP_PRIVATE_KEY    | (Output from first kubectl command)  |
    | SAML_SP_CERTIFICATE    | (Output from second kubectl command) |

5) (Optional) In the .env file, also set the following parameters:

* UMD_HANDLE_SERVER_URL - URL of the Handle server (i.e.,
    <https://handle-test.lib.umd.edu/>)
* UMD_HANDLE_JWT_TOKEN - JWT Token for accessing the Handle server. See
    <https://github.com/umd-lib/umd-handle#jwt-tokens> for more information.
* IP_MANAGER_SERVER_URL - URL of the IP Manager server (i.e.,
    <https://ipmanager-test.lib.umd.edu>)

6) **(M-series)** Edit the "config/environments/development.rb" file:

    ```zsh
    vi config/environments/development.rb
    ```

    and commenting out the line:

    ```text
    config.file_watcher = ActiveSupport::EventedFileUpdateChecker
    ```

    by changing it to:

    ```text
    # config.file_watcher = ActiveSupport::EventedFileUpdateChecker
    ```

7) Retrieve the Docker images necessary to run Avalon:

    ```zsh
    docker-compose pull
    ```

8) **(M-series)** Build the "avalonmediasystem/fedora:4.7.5" for the "arm64"
   architecture:

    a) In a separate terminal and directory, clone the
      "avalonmediasystem/avalon-docker" GitHub repository and switch into the
      directory:

      ```zsh
      git clone https://github.com/avalonmediasystem/avalon-docker.git
      cd avalon-docker/fedora
      ```

    b) Build the "avalonmediasystem/fedora:4.7.5" Docker image:

      ```zsh
      docker build -t avalonmediasystem/fedora:4.7.5 .
      ```

    c) Close the terminal (the directory containing the
       "avalonmediasystem/avalon-docker" checkout can also be deleted, if
       desired). The remaining steps should be done in the original
       terminal and directory with the "umd-lib/avalon" checkout.

7) Start the server

    ```bash
    docker-compose up avalon worker
    ```

Avalon should be available at: [http://av-local:3000](http://av-local:3000)

**Known issue**:  Both, umd-handle web app and avalon web app use SAML certificates that require them to run on port 3000. When testing Avalon integration with umd-handle, run the umd-handle server on a different port (e.g. 3001). As Avalon uses JWT authentication to talk to the umd-handle REST API, the umd-handle integration can be tested without requiring a working SAML setup for umd-handle.

See [Readme](./README.md#Development) for more information.

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
* MATOMO_ANALYTICS_CDN_SRC = CDN URL to the UMD Matomo JavaScript script

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

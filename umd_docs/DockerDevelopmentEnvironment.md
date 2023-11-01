# Docker Development Environment

This document contains instructions for building a local development instance
of Avalon using Docker.

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

1) Checkout the application and switch to the directory:

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

   **Note:** If integrating with the umd-handler application running locally,
   see the ["umd-handle Integration"](#umd-handle-integration) section below.

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

    a) Switch to the directory containing the "avalon" clone as a subdirectory,
       clone the  "avalonmediasystem/avalon-docker" GitHub repository and switch into the
       directory:

      ```zsh
      cd ..
      git clone https://github.com/avalonmediasystem/avalon-docker.git
      cd avalon-docker/fedora
      ```

    b) Build the "avalonmediasystem/fedora:4.7.5" Docker image:

      ```zsh
      docker build -t avalonmediasystem/fedora:4.7.5 .
      ```

    c) Switch back to the "avalon" directory (with the remaining steps done
       in the directory with the "umd-lib/avalon" checkout):

      ```zsh
      cd ../../avalon
      ```

9) Start the server

    ```bash
    docker-compose up avalon worker
    ```

   **Note:** Avalon may take 5-10 minutes to become available -- look for the
   following in the log output:

   ```text
   avalon-avalon-1  | => Booting WEBrick
   avalon-avalon-1  | => Rails 6.0.5.1 application starting in development http://0.0.0.0:3000
   avalon-avalon-1  | => Run `rails server --help` for more startup options
   ```

   Avalon should be available at: [http://av-local:3000](http://av-local:3000)

### Loading Sample Data

Sample data for Avalon is available in the
"SSDR/Developer Resources/avalon-sample-data" folder in Box -
<https://umd.app.box.com/folder/156055839002>. See the "README.boxnote"
in the folder for a description of each dataset.

1) In a web browser go to

   <http://av-local:3000/>

   Sign in to Avalon the "Sign In" button.

2) After signing in, create a "Test Collection" by selecting
   "Manage | Manage Content" from the navigation bar. On the resulting page,
   left-click the "Create Collection" button. In the "Create Collection"
   dialog, enter the following:

   | Field | Value          |
   | ----- | -------------- |
   | Name  | Test Collection|

   then left-click the "Create Collection" button in the dialog. Once created,
   the "Manage Content" page with the collection will be displayed. Also, a
   "masterfiles/dropbox/Test_Collection/" subdirectory will be created in the
   Avalon project directory.

3) In a terminal, add a `sample-data@example.com` admin user (which is the
   email address of the submitter in the sample datasets) by executing a Bash
   shell in the "avalon-avalon-1" Docker container:

   ```zsh
   docker exec -it avalon-avalon-1 /bin/bash
   ```

   and running the following command:

   ```zsh
   rails avalon:user:create \
     avalon_username=sample-data@example.com avalon_password=PASSWORD \
     avalon_groups=administrator
   ```

   then exit the Docker container:

   ```zsh
   exit
   ```

4) Download the "Sample_Audio_and_Video" folder (as a Zip file) from
   <https://umd.app.box.com/folder/156055839002> and place it in the
   "masterfiles/dropbox/Test_Collection/" folder. In a terminal,
   switch to the "masterfiles/dropbox/Test_Collection/" subdirectory:

   ```zsh
   cd masterfiles/dropbox/Test_Collection/
   ```

   and extract the file:

   ```zsh
   unzip Sample_Audio_and_Video.zip
   ```

   and extract the file.

5) The "avalon-worker" container scans the "masterfiles/dropbox" directory
   once a minute, and ingests any new items found. Depending on the size
   of the dataset, and the need to transcode the content, the ingest may
   take several minutes.

6) Once the ingest has started, the "Test Collection" folder should be
   visible to administrators in the Avalon interface on the "My Collections"
   page (reachable via "Manage | Manage Content" on the navigation bar), and
   on the "Browse" and "Collections" pages.

   The collection must have at least one published item before being displayed
   to anonymous users on the "Browse" or "Collections" pages.

   **Note:** The first ingest after Avalon starts often seems. If nothing is
   loaded for the collection, extract the dataset Zip file again (this restores
   the manifest spreadsheet, which is deleted as part of the ingest process),
   and the second try should be successful.

7) To publish an item, select the item from the "Browse" page. On the item
   detail page, left-click the "Publish" button. A notification should be
   displayed indicating that the item was successfully published.

### Running the tests

To run the Avalon tests:

1) In the "avalon" project directory, start the "test" Docker Compose stack:

    ```zsh
    docker-compose up test
    ```

2) In a second terminal, run a Bash shell in the "avalon-test-1" container:

    ```zsh
    docker exec -it avalon-test-1 /bin/bash
    ```

3) In the Docker container, install the gems:

   ```zsh
   bundle install
   ```

4) Run the tests:

    ```zsh
    bundle exec rspec
    ```

   **Note:** Running all the tests will likely take about 5 hours. To run
   individual tests, supply the path of the RSpec file to test, for example:

    ```zsh
    bundle exec rspec spec/controllers/access_tokens_controller_spec.rb
    ```

## umd-handle Integration

When testing Avalon integration with umd-handle, run the umd-handle server on a
different port (e.g. 3001).

The following instructions assume that the umd-handle server is running
on the local workstation (not in Docker).

Both umd-handle and Avalon use SAML certificates that expect the applications
to run on port 3000. Therefore, it will not be possible to log in to the
umd-handle website when running on port 3001, because the UMD CAS server is
configured to only respond to the "handle-local" hostname on port 3000.
As Avalon uses a JWT token (instead of CAS) to authenticate to the umd-handle
REST API, the umd-handle integration can still be tested.

### umd-handle Setup

1) Update the "config/application.rb" file in "umd-handle" to enable the
   application to accept the `host.docker.internal` host as an allowed host:

   ```bash
       # HOST should be ignored (and config.hosts not set) when running the tests.
       if ENV['HOST'].present? && !Rails.env.test?
         ...
       end

       ### Add this line ###
       config.hosts << 'host.docker.internal'
   ```

2) Edit the ".env" file:

   ```zsh
   # Run in the "umd-handle" application directory
   vi .env
   ```

   and set the `HANDLE_HTTP_PROXY_BASE` property to an arbitrary URL such as

   ```text
   HANDLE_HTTP_PROXY_BASE=http://hdl-local.lib.umd.edu/
   ```

3) To run the umd-handle application on a different port, start the application
   with a "PORT" environment variable set to the desired port. For example, to
   run on port 3001:

   ```zsh
   # In the "umd-handle" directory
   PORT=3001 bundle exec rails server
   ```

### Avalon Setup

1) Get a JWT token from the "umd-handle" application (see
   <https://github.com/umd-lib/umd-handle#jwt-tokens>), by running the following
   command in the "umd-handle" directory:

   ```zsh
   # Run in the "umd-handle" application directory
   bundle exec rails 'jwt:create_token["Avalon JWT Token"]'
   ```

2) In the "avalon" directory, edit the ".env" file:

   ```zsh
   # Run in the "avalon" application directory
   vi .env
   ```

   a) When running the umd-handle application on the local workstation (outside of
      Docker), Avalon and umd-handle will be on different networks. The
     the `UMD_HANDLE_SERVER_URL` property should be set to:

   ```text
   UMD_HANDLE_SERVER_URL=http://host.docker.internal:3001/api/v1/handles
   ```

   b) Set the `UMD_HANDLE_JWT_TOKEN` property to the output from Step 1:

   ```text
   UMD_HANDLE_JWT_TOKEN=<Output from Step 1>
   ```

### Verifying umd-handle integration

To verify that the integration with the "umd-handle":

1) Load sample data into Avalon.

2) Publish an item

3) On the item detail page, left-click the "Share" button. The list of URLs
   should include a handle URL (using the `HANDLE_HTTP_PROXY_BASE` as a
   prefix) such as `http://hdl-local.lib.umd.edu/1903.1/1`

## Advanced Setup

These following changes enable the "avalon" and "worker" processes to be
started, stopped, and restarted independently. The changes also provide
access to the "byebug" console for interactive debugging.

1) Modify the Docker Compose stack, so that the "avalon" and "worker" Docker
   images simply start a Bash shell, instead of the Avalon application. To do
   this, modify the "docker-compose.yml" file, changing the `command` directive
   rom:

   ```yaml
     avalon: &avalon
       image: avalonmediasystem/avalon:7.1-slim-dev-20200807
       build:
         context: .
         target: dev
       command: bash -c "/docker_init.sh && bin/rails server -b 0.0.0.0"

   ...

     worker:
       <<: *avalon
       command: dumb-init -- bash -c "bundle install && bundle exec sidekiq -C config/sidekiq.yml"
   ```

   to

   ```yaml
     avalon: &avalon
       image: avalonmediasystem/avalon:7.1-slim-dev-20200807
       build:
         context: .
         target: dev
       command: bash

   ...

     worker:
       <<: *avalon
       command: dumb-init -- bash
   ```

2) Start the docker-compose stack:

   ```zsh
   docker-compose up avalon worker
   ```

3) In separate terminals, use "docker exec" to access and initialize both the
   "avalon-avalon-1" and "avalon-worker-1" containers:

   ```zsh
   $ docker exec -it avalon-avalon-1 /bin/bash
   avalon-avalon-1$ /docker_init.sh
   ```

   ```zsh
   $ docker exec -it avalon-worker-1 /bin/bash
   avalon-worker-1$ bundle install
   ```

4) Run the Avalon application in each Docker container:

   ```zsh
   avalon-avalon-1$ bin/rails server -b 0.0.0.0
   ```

   ```zsh
   avalon-worker-1$ bundle exec sidekiq -C config/sidekiq.yml
   ```

   The applications can now be started/stopped as needed, and the "byebug"
   console will be accessible for use.

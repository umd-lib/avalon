# Avalon

## Development Setup

Prerequisite:

Edit the "/etc/hosts" file and add

```text
127.0.0.1 av-local
```

1) Checkout the application and swtich to the directory:

    ```bash
    git clone git@github.com:umd-lib/avalon.git
    cd avalon
    ```

2) Copy the "env_example" file to ".env":

    ``` bash
    cp env_example .env
    ```

    Determine the values for the "SAML_SP_PRIVATE_KEY" and "SAML_SP_CERTIFICATE"
    variables:

    ```bash
    kubectl -n test get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_PRIVATE_KEY}' | base64 --decode
    kubectl -n test get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_CERTIFICATE}' | base64 --decode
    ```

    Edit the '.env" file:

    ```bash
    vi .env
    ```

    and set the parameters:

    | Parameter              | Value                                |
    | ---------------------- | ------------------------------------ |
    | SAML_SP_PRIVATE_KEY    | (Output from first kubectl command)  |
    | SAML_SP_CERTIFICATE    | (Output from second kubectl command) |

3) Start the server

    ```bash
    docker-compose pull
    docker-compose up
    ```

Avalon should be available at: [http://av-local:3000](http://av-local:3000)

**Known issue**:  Both, umd-handle web app and avalon web app use SAML certificates that require them to run on port 3000. When testing Avalon integration with umd-handle, run the umd-handle server on a different port (e.g. 3001). As Avalon uses JWT authentication to talk to the umd-handle REST API, the umd-handle integartion can be tested without requiring a working SAML setup for umd-handle.

See [Readme](./README.md#Development) for more information.

## SAML Environment Specific Configuration

The following varaibles were added to facilate configuring environment
specific SAML configuration. These environment varaibles will take
precedence over the configuration in the [settings.yml](./config/settings.yml).

- `SAML_ISSUER`: Overrides the `issuer` configuration.
- `SAML_SP_PRIVATE_KEY`: Overrides the `private_key` configuration.
- `SAML_SP_CERTIFICATE`: Overrides the `certificate` configuration.

## Docker Build for K8s Deployment

The k8s-avalon stack uses the avalon image built from this repository.

1. Build and tag the image

    ```bash
    # Substitute IMAGE_TAG with appropriate value
    # Example IMAGE_TAG values for differnt scenarios:
    #    Dev Build: docker.lib.umd.edu/avalon:latest
    #    RC Build: docker.lib.umd.edu/avalon:7.1-umd-0-rc2
    #    Release Build: docker.lib.umd.edu/avalon:7.1-umd-0
    #    Hotfix Build: docker.lib.umd.edu/avalon:7.1-umd-0.1
    docker build -t IMAGE_TAG .
    ```

2. Push it to UMD Nexus

    ```bash
    # Substitute IMAGE_TAG with appropriate value
    docker push IMAGE_TAG
    ```

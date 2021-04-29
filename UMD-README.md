# Avalon

## Development Setup

```
docker-compose pull
docker-compose up avalon
```

Avalon should be available at: http://av-local:3000

See [Readme](./README.md#Development) for more information.

## SAML Environment Specific Configuration

The following varaibles were added to facilate configuring environment
specific SAML configuration. These environment varaibles will take
precedence over the configuration in the [settings.yml](./config/settings.yml).

- `SAML_ISSUER`: Overrides the `issuer` configuration.
- `SAML_SP_PRIVATE_KEY`: Overrides the `private_key` configuration.
- `SAML_SP_CERTIFICATE`: Overrides the `certificate` configuration.

### SAML Local Development environment setup

The SAML SP signing certificates needs to be configured for SAML to work
on the local development environment.

```
# Copy the env_example to .env
cp env_template .env

# Get the private_key from avalon test environemnt
kubectl get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_PRIVATE_KEY}' | base64 --decode

# Get the certificate from avalon test environemnt
kubectl get secret avalon-common-env-secret -o jsonpath='{.data.SAML_SP_CERTIFICATE}' | base64 --decode

# Update .env file with values retrieved from the test environment
vim .env
```

## Docker Build for K8s Deployment

The k8s-avalon stack uses the avalon image built from the repository.

1. Build and tag the image

    ```
    # Substitute IMAGE_TAG with appropriate value
    # Example IMAGE_TAG values for differnt scenarios:
    #    Dev Build: docker.lib.umd.edu/avalon:latest
    #    RC Build: docker.lib.umd.edu/avalon:7.1-umd-0-rc2
    #    Release Build: docker.lib.umd.edu/avalon:7.1-umd-0
    #    Hotfix Build: docker.lib.umd.edu/avalon:7.1-umd-0.1
    docker build -t IMAGE_TAG .
    ```

2. Push it to UMD Nexus

    ```
    # Substitute IMAGE_TAG with appropriate value
    docker push IMAGE_TAG
    ```

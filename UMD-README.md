# Avalon

To be updated!

## Docker Build for K8s Deployment

The k8s-avalon stack uses the avalon image built from the repository.

1. Build and tag the image

    ```
    # Substitute IMAGE_TAG with appropriate value
    # Example IMAGE_TAG values for differnt scenarios:
    #    Dev Build: docker.lib.umd.edu/avalon:7.1-umd-0-alpha4
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

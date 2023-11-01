# umd-handle Integration

## Introduction

This document provides information about the integration of Avalon with the
"umd-handle" application for minting Handle.net handles.

Information about setting up Avalon to integrate with the "umd-handle"
application in the local development environment can be found in
[docs/DockerDevelopmentEnvironment.md](DockerDevelopmentEnvironment.md).

## Useful Resources

* <https://github.com/umd-lib/umd-handle>

## Functionality

The Avalon integration with the "umd-handle" application enables the "minting"
of a Handle.net handle when publishing an item.

The process is fully automatic, and does not require any user interaction.

The handle for an item can be found by left-clicking the "Share" button on
the detail page for the item.

## Environment Variables

The following environment variables support the "umd-handle" integration:

* UMD_HANDLE_SERVER_URL - The URL to the handle "minting" endpoint on the
  "umd-handle" server, for example: `http://host.docker.internal:3001/api/v1/handles`
* UMD_HANDLE_JWT_TOKEN - The JWT token to use to authenticate to the
  "umd-handle" server.
* UMD_HANDLE_PREFIX - The handle prefix to use for minted handles, for example: `1903.1`
* UMD_HANDLE_REPO - The name of the repository to provide to the "umd-handle"
  server. For Avalon, this should always be `avalon`

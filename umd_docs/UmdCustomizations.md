# UMD Customizations

## Introduction

This document provides information and links for the UMD customizations made to
the stock Avalon code.

## Major Customizations

Major customizations have their own documents:

* [Avalon Permissions](./AvalonPermissions.md)
* [UMD Handle Integration](./UmdHandleIntegration.md)

## Minor Customizations

### Aeon - "Request from Special Collections" functionality

Provides a "Request from Special Collections" button on the media object detail
page that submits a pre-populated Aeon form to request the item from
Special Collections.

The pre-populated form is submitted with the following settings:

| Avalon MediaObject Model Field     | Form input name | Aeon Field                   |
| ---------------------------------- | --------------- | ---------------------------- | 
| title                              | ItemTitle       | Title                        |
| date_issued                        | ItemDate        | Date                         |
| collection.name                    | Location        | Location                     |
| other_identifier (comma-separated) | CallNumber      | Call Number/Accession Number |
| permalink                          | ReferenceNumber | Catalog Record ID            |

Initially implemented in
[LIBAVALON-93](https://umd-dit.atlassian.net/browse/LIBAVALON-93).

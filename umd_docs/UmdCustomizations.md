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

### Master File Downloads

#### Master File Downloads - Pre-Avalon 7.8 Functionality

* "Downloads" button - [LIBAVALON-213][libavalon213]
* "Downloads" panel - [LIBAVALON-197][libavalon197]

Prior to the upgrade to Avalon 7.8, the "master file" downloads functionality
consisted of the following elements on the media object detail page:

* A "Download" button next to the "Share" button in the main section of the page
* A "Downloads" panel below to the "Details" panel in the right sidebar.

These GUI elements were only shown when users had the "master_file_download"
permission.

#### Master File Downloads - Current Functionality

* [LIBAVALON-398][libavalon398]

Changes to the media object detail page in Avalon 7.7 made the UMD
customizations for the "master file" downloads obsolete. In re-implementing
the customization, only the functionality of the "Download" panel was retained
(in a different form) -- the "Download" button was *not* re-implemented.

In Avalon 7.7, the media object detail page was changed to use the
"MediaObjectRamp" React component to provide the media player and the
"Details" panel in the right sidebar. This React component incorporates
React components from the [@samvera/ramp](https://github.dev/samvera-labs/ramp)
JavaScript package.

The right sidebar, which typically just displays the "Details" panel, is capable
of displaying additional panels in a tabbed layout. In stock Avalon, an
additional "Files" tab can be displayed, which uses the "SupplementalFiles"
from the "@samvera/ramp" package to enable the download of the "supplemental" files
associated with the media object, via a "SupplementalFiles" React component.

UMD has modified the "MediaObjectRamp" to customize the "Files" tab by adding
an additional "UmdMasterFiles" React component, which is placed along with the
"SupplementalFiles" React component in the "Files" tab so that the
"master file(s)" for the media object can also be downloaded (assuming that the
user has the "master_file_download" permission).

With this change, all the files a typical user might wish to download are
available in one location in the GUI. Because of this, it was decided that
a separate "Download" button was not needed, and so it not implemented in
Avalon 7.8 and later versions.

----
[libavalon197]: https://umd-dit.atlassian.net/browse/LIBAVALON-197
[libavalon213]: https://umd-dit.atlassian.net/browse/LIBAVALON-213
[libavalon398]: https://umd-dit.atlassian.net/browse/LIBAVALON-398
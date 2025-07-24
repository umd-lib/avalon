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

Provides a user with the "master_file_download" permission the following
functionality on the media object detail page:

* A "Download" button next to the "Share" button in the main section of the page
* A "Downloads" tab next to the "Details" tab in the right sidebar.

In cases where a media object has more than one master file, the user can
any or all of the master files.

If the user does not have "master_file_download" permission, the
"Download" button and the "Downloads" tab are *not* displayed.

Note: The "access token" functionality provides an option to allow the token
holder to download the master files (i.e., granting them the
"master_file_download" permission), so the "Download" button and "Downloads"
tab are shown for these token holders.

#### Download button

The "Download" button opens up a modal dialog, which shows a bulleted list of
the available downloads.

#### Downloads tab

In the original [LIBAVALON-197][libavalon197] implementation, this was a
"Downloads" panel underneath the "Details" panel in the right sidebar.

With the introduction of the MediaObjectRamp component in Avalon 7.7, the
panel was changed to a "Downloads" tab that appears alongside the "Details"
tab in the right sidebar, and shows a bulleted list of links, and is displayed
next to the "Details" tab in the right sidebar.

#### Master File Downloads - Additional Information

Additional information about the Download functionality can be found in:

* "Downloads" button - [LIBAVALON-213][libavalon213]
* "Downloads" panel - [LIBAVALON-197][libavalon197]
* "Access token" functionality - [LIBAVALON-198][libavalon198]
* Avalon 7.8 re-implementation - [LIBAVALON-398][libavalon398]

----
[libavalon197]: https://umd-dit.atlassian.net/browse/LIBAVALON-197
[libavalon198]: https://umd-dit.atlassian.net/browse/LIBAVALON-198
[libavalon213]: https://umd-dit.atlassian.net/browse/LIBAVALON-213
[libavalon398]: https://umd-dit.atlassian.net/browse/LIBAVALON-398

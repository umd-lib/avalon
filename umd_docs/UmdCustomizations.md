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

### Restricted Playback Message

Added a narrower CanCan ability with a permission scope that allows users to
view item metadata without being able to play back the media. When users view an
item with that permission scope, they will see a restricted playback message
asking them to connect to a VPN to stream the content. Additionally, restricted
items in the Jim Henson collection will display a message asking users to access
the items from specific physical library locations. The item's collection name
is checked for the presence of the string "jim henson" in a case-insensitive
manner to determine if it is part of the Jim Henson collection.

Optional Configuration:

The default search string "jim henson" for the Jim Henson collection can be
overridden by setting the following environment variable:

```txt
SETTINGS__JIM_HENSON_COLLECTION__MATCH_STRING="henson collection"
```

Note: The string is compared to the lower-cased collection name to make the
check case-insensitive.

Jira links:

* [Initial implementation - LIBAVALON-168](https://umd-dit.atlassian.net/browse/LIBAVALON-168)
* [Refactor for Avalon 7.8 - LIBAVALON-403](https://umd-dit.atlassian.net/browse/LIBAVALON-403)

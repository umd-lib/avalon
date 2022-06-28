# Avalon Permissions

## Introduction

This document provides a summary of the "stock" Avalon permissions, and
subsequent modifications made to it by UMD.

## Useful Resources

* <https://samvera.atlassian.net/wiki/spaces/AVALON/pages/1957955268/Setting+Item+Access+Control>

## Stock Avalon Permissions

Quotes from: <https://samvera.atlassian.net/wiki/spaces/AVALON/pages/1957955268/Setting+Item+Access+Control>

A stock Avalon has the following settings controlling access:

* Published/Unpublished

    > ... instructions for setting Access Control and granting Special Access
    > refer specifically to published items. Unpublished items, regardless of
    > their access levels, are viewable only by collection members.

* Item Discovery

    > ... "Hide this item from search results" can be used to make an item
    > available via URL only, and the item will not appear using browse or
    > search.

* Item access

    > * Available to the general public: anyone can view this item, even if they
    >   are not logged in as a user.
    > * Logged in users only: only logged-in users may view this item. The item
    >   will also not display in search results to the general public.
    > * Collection staff only: only logged-in collection staff may view this item,
    >   which includes Managers, Editors, and Depositors.

* Assign special access

    > Beyond the basic access control levels defined above, special access can
    > be given to individual users, specific groups of users, and certain IP
    > addresses or range of IP addresses.

In a stock Avalon, a viewable/accessible item is streamable – i.e., if a user
can view/access an item, that user can stream the item.

## UMD Access Dimensions

UMD has modified the Avalon access setting as follows:

* Unpublished items should only be viewable/accessible by collection members.
* Published Items are viewable/accessible by default, where
  "viewable/accessible" indicates that the individual detail page (containing
  the item metadata) is available. Does not control whether the item is
  streamable.
* Item access/Assign special access controls whether an item is streamable – but
  only for published items

UMD has also added the concept of "access tokens", which are an additional
"Assign special access" option, using JWT tokens. These tokens control
whether a published item is streamable and/or downloadable.

### Publication Status

* Unpublished - Item is only viewable/streamable/downloadable by Collection
  staff, does not appear in Browse/Search, and is not
  viewable/streamable/downloadable by any mechanism​ by non-Collection staff
* Published - Item is accessible/viewable by any user (including anonymous
  users)

### Item Discovery

For published items:

* Item Discovery allowed​ - Item appears in Browse/Search​
* Item Discovery disabled - Item does not appear in Browse/Search, but is
  directly accessible by URL

### Item Access

For published items, controls whether an item is streamable:

* ​Available to the general public - Streamable by anyone, even anonymous users
* Logged in users only - Streamable by logged-in users
* Collection staff only - Streamable by collection staff

    ----
    **Note for developers**

    Item Access is implemented using the "visibility" field on MediaObject,
    which has the following values:

    |"visibility" field value|Item Access|
    | ---------------------- | --------- |
    |​public                  | Available to the general public |
    |restricted              | Streamable by logged-in users |
    |private                 | Streamable by collection staff |
    ----

### Assign Special Access

For published items, the set of users allowed to stream an item can be expanded
using the "Assign special access" criteria:

* ​Avalon User - Named Avalon user can stream item
* External Group - Member of external group can stream item
* IP Address or Range - User from IP address in given range can stream item
* UMD IP Manager - User with an IP address matching an IP Manager group can
  stream item

### Access Token

For published items, a user presenting an access token may "stream", "download",
or "stream and download" a published item, based on the access token setting.

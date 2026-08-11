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
* Published - Item is viewable by any user (including anonymous users) whatever
  its Item Access setting, unless Item Discovery has been disabled for it (see
  below)

### Item Discovery

For published items:

* Item Discovery allowed​ - Item appears in Browse/Search​
* Item Discovery disabled - Item does not appear in Browse/Search, and the broad
  metadata read above is withdrawn: the item page is viewable only by users the
  item's access controls actually admit. Everyone else gets a "Restricted
  Content" message and a "401 Unauthorized" response.

  **Hiding an item never removes access that its access controls grant.** It is
  a discovery setting, so whoever could view the item can still reach it by
  direct URL:

  | Item Access, item hidden | Anonymous user | Logged in user |
  | --- | --- | --- |
  | Available to the general public | Item page | Item page |
  | Logged in users only | 401 | Item page |
  | Collection staff only | 401 | 401 |

  Collection staff (who have edit access), users/groups/IP ranges granted read
  via "Assign special access", and holders of a valid access token URL can view
  the item in every row. Items in the Streaming Reserves unit are unaffected —
  they have their own access rule.

  The same is true whether Item Access was set on the item or inherited from the
  collection.

Like Item Access, Item Discovery is inherited from the parent collection by
default, and an item can override that inheritance via "Disable parent
permissions". An item is discoverable when the item itself is not hidden **and**
either it has overridden inheritance or its collection is not hidden.

**Item Discovery is independent of Item Access.** Items in a collection are
publicly discoverable by default regardless of their Item Access setting, so an
item whose access is "Collection staff only" still appears in Browse/Search for
anonymous users — they can see its metadata but cannot stream it. The exception
is collections in the Course Reserves (Streaming Reserves) unit, whose items are
discoverable only to the groups configured on the collection.

----
**Note for developers**

Collection-level discoverability is indexed on the collection as
`inheritable_discover_access_group_ssim`, which is `default_read_groups` plus
`public` for ordinary collections and `default_read_groups` alone for Course
Reserves collections (`Admin::Collection#to_solr`). Browse/Search filtering
happens in `SearchBuilder#limit_to_inheritance_enabled_items` and
`#limit_to_non_hidden_items`; the matching direct-URL check is the `cannot :read`
rule in `Ability#custom_permissions`, built from
`Ability#discoverability_allows_read?` (which mirrors `#limit_to_non_hidden_items`)
plus `#access_controls_allow_read?` and `#access_token_allows_read?`, which are
what keep a hidden item reachable by whoever its access controls admit.

Browse/Search and the item page are deliberately **not** symmetrical here: a
hidden public item is absent from search results but renders on direct URL. What
must stay in agreement is the hidden/not-hidden determination itself —
`#discoverability_allows_read?` and `#limit_to_non_hidden_items` have to classify
the same items as hidden, or an item disappears from search for reasons the item
page does not apply (or the reverse).

**Changing this setting on existing content requires a reindex.** Because
`inheritable_discover_access_group_ssim` is written by `Admin::Collection#to_solr`,
collections created before this field was introduced do not have it until they
are re-saved or reindexed, and their items will not be publicly discoverable
until then.

**Access token requests are not always identified by a query parameter.** An
access token URL carries the token as `?access_token=`, but the item page issues
sub-requests the player builds itself from bare paths — most importantly
`/media_objects/:id/manifest.json` — which do not inherit it. So
`ApplicationController#current_ability` also accepts the token from the referring
page's URL (`#access_token_from_referer`), the same lookup
`MasterFilesController#hls_manifest` uses to authorize streaming. Anything that
newly denies `:read` on a media object must be checked against these
sub-requests, not just against the item page: before this fallback existed, a
hidden item loaded via an access token rendered its page but the player failed
with "Failed to fetch Manifest."

----

### Item Access

For published items, Item Access controls whether an item is streamable:

* Available to the general public – Streamable by anyone, even anonymous users
* Logged in users only – Streamable by logged-in users
* Collection staff only – Streamable by collection staff

By default, an item's Item Access setting inherits from its parent collection.
For most collections, the collection-level setting is configured to match the
intended behavior for the majority of items, and those items simply inherit that
collection-level access. When mixed access is needed within a collection,
individual items can override inheritance (via “Disable parent permissions”) and
use their own Item Access setting instead.

----
**Note for developers**

Item Access is implemented using the "visibility" field on MediaObject, which
has the following values:

|"visibility" field value|Item Access|
| ---------------------- | --------- |
|public                  | Available to the general public |
|restricted              | Streamable by logged-in users |
|private                 | Streamable by collection staff |

Under the inheritance model, the effective visibility used for streaming is
derived from the collection-level setting unless the item has explicitly
disabled parent permissions and set its own visibility.

----

### Assign Special Access

For published items, the set of users allowed to stream an item can be expanded
using the "Assign special access" criteria. Special access is additive on top of
the effective Item Access (whether inherited from the collection or overridden
at the item level):

* Avalon User – Named Avalon user can stream item
* External Group – Member of external group can stream item
* IP Address or Range – User from IP address in given range can stream item
* UMD IP Manager – User with an IP address matching an IP Manager group can
  stream item

### Access Token

For published items, a user presenting an access token may "stream", "download",
or "stream and download" a published item, based on the access token setting.

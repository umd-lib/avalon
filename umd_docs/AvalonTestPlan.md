# Avalon Test Plan

## Introduction

This document provides a basic Avalon test plan that verifies as many UMD
customizations and other concerns (such as functionality when using read-only
containers) as feasible.

The intention is to provide basic assurance that the UMD customizations are in
place, and guard against regressions.

**The document is not intended to be an exhaustive test plan.**

As this test plan adds, modifies, and deletes data, it should ***not*** be used
to test the production system.

## Test Plan Assumptions

This test plan assumes that:

* the "umd-handle", "ipmanager", and "archelon" applications are also running
  in the Kubernetes namespace being tested.
* the user has "administrator" privileges, and can log in via CAS.
* the user has a video file to upload, such as a video file from the
  "SSDR/Developer Resource/savalon-sample-data" folder in Box.
* (optional) the user has an SSH public key registered with the Archelon
  instance running in the Kubernetes namespace (needed for the "SFTP Access"
  step).

The test plan steps are specified using URLs for the Kubernetes "test"
namespace, as that seems to be the most useful. Unless otherwise specified,
test steps should work in the local development environment as well.

## Test Plan

### 1) Avalon Home Page

1.1) In a web browser, go to

<https://av-test.lib.umd.edu/>

The Avalon home page will be displayed.

1.2) On the Avalon home page, verify that:

* The UMD favicon is displayed in the browser tab, and that the text in
  the browser tab is "Avalon"
* The appropriate SSDR environment banner is displayed.

1.3) At the bottom of the page, verify that the footer has the following links:

* "Give Now"
* "Privacy policy"
* "Web Accessibility"

1.3.1) Left-click the "Give Now" link. Verify that the "Giving to Maryland" page
on the university website is displayed.

1.3.2) Go back to the Avalon home page, and left-click the "Privacy policy" link.
Verify that the privacy policy page from the UMD Libraries website is displayed.

1.3.3) Go back to the Avalon home page, and left-click the "Web Accessibility"
link. Verify that the web accessibility page on the university website is
displayed.

### 2) CAS Login

2.1) On the Avalon home page, left-click the "Sign in" button in the upper-right
corner of the page. Verify that the browser is redirected to CAS.

2.2) Log in via CAS. Once returned to the Avalon home page, verify that your
user's email address (and a "Sign out" link) are displayed in the upper-right
corner of the page, along with a notification indicating a successful login.

### 3) Collection Creation

3.1) From the navigation bar, select "Manage | Manage Content" from the
navigation bar. The "My Collections" page will be displayed.

3.2) Create a new collection by left-clicking the "Create Collection" button.
The "New collection" page will be displayed.

3.3) On the "New collection" page, fill out the following fields:lds:

| Field | Value |
| ----- | ----- |
| Name  | SSDR Test Collection |
| Unit  | <Select "Special Collections in Performing Arts" from the dropdown> |

then left-click the "Create Collection" button. A notification will display
indicating that the collection was successfully created.  A
"Manage Content | SSDR Test Community" page will be displayed.

### 4) Item Submission

4.1) On the "Manage Content | SSDR Test Community" page, left-click the
"Create an Item" button. The "Edit Media Object > Manage files" page will be
displayed.

4.2) On the “Edit Media Object > Manage files” page, left-click the
“Select file” button in the “Section files” section. In the resulting file
dialog, select a video file, and then left-click the “Upload” button. Once the
upload is complete, verify that that a notification is displayed indicating that
the uploaded content is a video file. Left-click the “Continue” button at the
bottom of the page. The “Edit Media Object > Resource description” page will
be displayed.

4.3) On the “Edit Media Object > Resource description” page, fill out the
following fields:

| Field | Value |
| ----- | ----- |
| Name  | SSDR Test Item |
| Publication Date | <Enter a date in YYYY-MM-DD format, i.e., `2025-08-27`> |

then left-click the “Save and continue” button at the bottom of the page. The
“Edit Media Object > Structure” page will be shown.

4.4) On the “Edit Media Object > Structure” page, left-click the “Continue”
button. The “Edit Media Object > Access Control” page will be shown.

4.5) On the “Edit Media Object > Access Control” page, left-click the
"UMD IP Manager" dropdown and verify that it is populated with one or more
entries (these entries are the "exported" groups from IP Manager).

Left-click the “Save and continue” button at the bottom of the page. The item
detail page for the item will be displayed.

4.6) On the item detail page, wait for the conversion process to complete
(if necessary), then left-click the “Publish” button to publish the item.
The item detail page will refresh. Verify that the page displays a notification
indicating that the page was successfully published.

4.7) On the item detail page, left-click the “Share” button to expand it. Verify
that the “Item” link has a handle URL appropriate for the Kubernetes namespace.
For example, for the Kubernetes "test" namespace the URL should have the form:

`https://hdl-test.lib.umd.edu/1903.1/<HANDLE_SUFFIX>`

where <HANDLE_SUFFIX> is a simple integer.

4.8) On the item detail page, verify that there is a
"Request from Special Collections" button above the right sidebar. Left-click
the "Request from Special Collections" anf verify that a new browser tab is
opened on the Aeon website. After logging in to Aeon, verify that
"New Duplication Request" page is displayed with the following fields
populated:

* Title - the title of the item
* Date - the publication date of the item
* Catalog Record ID - the handle URL for the item
* Location field - the name of the collection (i.e., "SSDR Test Collection")

Left-click the "Cancel - Return to Main Menu" button at the bottom of the page
and close the browser tab.

### 5) Access Token

5.1) On the item detail page, left-click the "Edit" button. The
"Edit Media Object > Access Control" page will be displayed.

5.2) On the "Edit Media Object > Access Control" page, add an access token by
left-clicking the "Create a new token" button. An access token form will be
displayed.

5.3) On the access token form, change the "Access" field to
"Streaming and Download" and left-click the “Save” button to generate an
access token for the media object. An access token detail page will be
displayed.

5.4) On the access token detail page, copy the access token URL near the bottom
of the page. Then in a private browser window, go to the URL and verify that
the media object detail page is shown. Verify that the video can be streamed,
and that a "Files" tab (allowing downloads) is displayed in the right
sidebar.

5.5) Left-click the "Files" tab, and then left-click the file link in the
"Media Files" section to download the file. Verify that the file downloads
successfully.

5.6) On the access token detail page, left-click the "Revoke" button. Verify
that the page is updated and now indicated that the status of the access token
is "Revoked".

5.7) Refresh the private browser window and verify that a "Playback Restricted"
panel is shown in place of the video, and that the "Files" tab is no longer
displayed in the right sidebar.

Close the private browser window.

5.8) On the access token detail page, left-click the "Access Tokens List"
button. The "Access Tokens" page will be displayed.

5.9) On the "Access Tokens" page verify that the token added in the previous
steps is *not* displayed (as it is not an active token). Change the
"Filter by status" dropdown to "revoked" and left-click the "Go" button.
Verify that the access token added in the previous steps is in the list.

### 6) robots.txt

**Note:** This step cannot be tested in the local development environment.

6.1) In a web browser go to

<https://av-test.lib.umd.edu/robots.txt>

Verify the contents of a "robots.txt" file is displayed.

### 7) sitemap.xml

**Note:** This step cannot be tested in the local development environment.

7.1) In a web browser go to

<https://av-test.lib.umd.edu/sitemap.xml>

Verify that a "sitemap" file is returned.

### 8) SFTP Access **(Optional)**

**Note:** This step cannot be tested in the local development environment, or
in the Kubernetes "sandbox" namespace.

----

This step requires an SSH public key registered with the Archelon
instance running in the Kubernetes namespace. To check the list of registered
keys use the "/public_keys" Archelon endpoint. For example in the "test"
namespace, the URL would be:

<https://archelon-test.lib.umd.edu/public_keys>

This step is optional, and can be skipped without affecting the later steps.

----

8.1) Log in to the Avalon SFTP server:

| Kubernetes Namespace | URL                      | Port |
| -------------------- | ------------------------ | ---- |
| test                 | sftp.av-test.lib.umd.edu | 31128 |
| qa                   | sftp.av-qa.lib.umd.edu   | 31107 |
| prod                 | sftp.av.lib.umd.edu      | 31107 |

For example, for the "test" namespace:

```zsh
$ sftp -P 31128 app@sftp.av-test.lib.umd.edu
```

----

**Note:** If you have trouble logging in, see the "Avalon Batch Upload"
Confluence page (<https://umd-dit.atlassian.net/wiki/spaces/LIB/pages/21432547>)
more information.

----

8.2) On the SFTP server, switch to the "dropbox" directory:

```bash
sftp$ cd dropbox
```

8.3) List the contents of the directory:

```bash
sftp$ ls
```

and verify that there is an "SSDR_Test_Collection" directory.

8.4) Log out from the SFTP server:

```bash
sftp$ exit
```

----

**Note:** For more information about batch uploads, including information
about how to perform an actual upload, see the "Avalon Batch Upload" Confluence
page.

----

### 9) Item Deletion

9.1) Go back to the item detail page of the item added in the previous steps.

9.2) On the item detail page, left-click the "Edit" button. The
"Edit Media Object > Access Control" page will be displayed.

9.3) On the "Edit Media Object > Access Control" page, left-click the
"Delete this item" button at the bottom of the left sidebar. A confirmation
page will be displayed.

9.4) On the confirmation page, left-click the "Yes, I am sure" button. The
Avalon home page will be displayed with a notification indicating that the
media object was deleted.

### 10) Collection Deletion

10.1) From the navigation bar, select "Manage | Manage Content" from the
navigation bar. The "My Collections" page will be displayed.

10.2) On the "My Collections" page, find the "SSDR Test Collection" entry in the
list and left-click the "Delete" button. A confirmation
page will be displayed.

10.3) On the confirmation page, left-click the "Yes, I am sure" button. The
"My Collections"" page will be displayed. Verify that the "SSDR Test Collection"
no longer appears in the list of collections.

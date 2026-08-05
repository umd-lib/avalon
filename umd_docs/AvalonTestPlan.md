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
navigation bar. The page will with units and collections will be displayed.

----

**Local Development Environment** <!-- markdownlint-disable-line MD036-->

When running in the local development environment, there may be no units
displayed on the page. If so, create a new unit,
`Special Collections in Performing Arts`, using the "Create New Unit" button
before proceeding to the next step.

After creating the unit, left-click  "Manage | Manage Content" from the
navigation bar to return to the page.

----

3.2) Create a new collection by left-clicking the "Create Collection" button.
The "New collection" page will be displayed.

3.3) On the "New collection" page, fill out the following fields:lds:

| Field | Value |
| ----- | ----- |
| Name  | SSDR Test Collection |
| Unit  | <Select "Special Collections in Performing Arts" from the dropdown> |

then left-click the "Create Collection" button. A notification will display
indicating that the collection was successfully created.  A
"Manage Collection | SSDR Test Collection" page will be displayed.

### 4) Item Submission

4.1) On the "Manage Collection | SSDR Test Collection" page, left-click the
"Create an Item" button. The "Edit Media Object > Manage files" page will be
displayed.

4.2) On the “Edit Media Object > Manage files” page, left-click the
“Browse...” button in the “Section files” section. In the resulting file
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
"Request This Item" button above the right sidebar. Left-click
the "Request This Item" button and verify that a new browser tab is
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

### 6) LTI Flow

**Note:** Steps 6.1 and 6.2 require access to a running Docker environment or
Kubernetes namespace. The rake task provisions a test course and user.

6.1) In a terminal, run the following rake task to provision a test LTI course
and user:

```bash
docker compose exec avalon bash -c "rails umd:provision_test_lti_course_and_user"
```

The task defaults to `context_id=test-course-context-id` and
`title=Test Course Title`. To customise, set the `TEST_LTI_COURSE_CONTEXT_ID`
and `TEST_LTI_COURSE_TITLE` environment variables.

6.2) From the navigation bar, select "Manage | Manage Content" to go to the
Manage Content page. Create a new unit named **Streaming Reserves** and
within it create a new collection named **Digitized Items**:

  a) Left-click the "+ Create Unit" button. On the "New unit" page, enter
     **Streaming Reserves** in the Name field, then left-click "Create Unit".
     The unit detail page for "Streaming Reserves" will be displayed.

  b) On the "Streaming Reserves" unit page, left-click the "Create Collection"
     button. On the "New collection" page, fill out the following fields:

     | Field | Value |
     | ----- | ----- |
     | Name  | Digitized Items |
     | Unit  | Streaming Reserves (pre-filled) |

  then left-click the "Create Collection" button. Verify that the collection
  is created successfully.

6.3) On the "Digitized Items" collection page, left-click the
"Create an Item" button and create a new item following the same steps as
section 4 (upload a video file, add a title and publication date, continue
through Structure, and reach the "Access Control" step).

6.4) On the "Edit Media Object > Access Control" page, add the test course as
an external group:

  a) In the **External Groups** field, start typing `Test Course` (or the
     title used in step 6.1). An autocomplete dropdown will appear with
     formatted values (Eg. 1: Test Course Title).

  b) Left-clicking on the test course entry in the dropdown should fill the
     formatted value in the External Groups field, then left-click the "Add"
     button.

  c) Verify that the page reloads and the formatted course title is listed
     under the **External Groups** section (Eg. _1:_ Test Course Title).

Left-click the "Save and continue" button. The item detail page will be
displayed.

6.5) Publish the item by left-clicking the "Publish" button on the item detail
page and verify that a success notification is displayed.

6.6) From the navigation bar, select "Manage | View Courses". The "Courses"
page will be displayed. Locate the test course created in step 6.1 and
left-click the "Browse Course Items" button next to it. 

6.7) Verify that the browse page is displayed, that the item created in step 6.3
is listed in the results, and that the left facet panel shows **Test Course
Title** (or the title used in step 6.1) pre-selected under the **Course Name**
facet.

6.8) From the navigation bar, select "Manage | View Courses". The "Courses"
page will be displayed. Locate the test course created in step 6.1 and
left-click the "Impersonate" button next to it.

6.9) Verify that the course view is displayed and that the item created in step
6.3 is listed in the course view.

6.10) In the browser, navigate to

<http://av-local:3000>

Verify that the home page renders correctly within the LTI session. Then
left-click the "Sign out" link and verify that the LTI session is ended
successfully.

### 7) robots.txt

**Note:** This step cannot be tested in the local development environment.

7.1) In a web browser go to

<https://av-test.lib.umd.edu/robots.txt>

Verify the contents of a "robots.txt" file is displayed.

### 8) sitemap.xml

**Note:** This step cannot be tested in the local development environment.

8.1) In a web browser go to

<https://av-test.lib.umd.edu/sitemap.xml>

Verify that a "sitemap" file is returned.

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

### 11) Collection-Level Discoverability for Restricted Streaming Items

This section verifies that items with restricted streaming access are still
discoverable to public (anonymous) users when discoverability is inherited
from a standard (non-Course-Reserves) collection.

> **Precondition:** Collection-level discoverability is driven by a Solr field
> (`inheritable_discover_access_group_ssim`) that is only written when a
> collection is saved or reindexed. Collections that existed before this change
> was deployed will not have it, and their items will not be publicly
> discoverable until they are reindexed. When testing against an existing
> collection, re-save the collection (or reindex it) first. Testing with a
> newly-created collection will pass regardless and will **not** exercise this.

**Shortcut:** sections 11 through 14 all begin by hand-building collections and
items with particular access settings. `rails umd:access_scenarios:provision`
creates that whole matrix in one step and prints a table of URLs with the result
expected of each persona, and `:teardown` removes it again. See
[AccessScenarioHarness.md](AccessScenarioHarness.md). The steps below remain the
authoritative manual procedure, and are still what to follow when verifying a
release by hand.

11.1) Log in to Avalon via CAS as an administrator. From the navigation bar,
select "Manage | Manage Content". The page with units and collections will be
displayed.

11.2) Create or identify a published item in a standard (non *Course Reserves*)
collection with the following access settings:

11.2.1) On the parent collection:

* Verify the collection is **not** a  *Course Reserves* collection.
* On the collection detail page, verify that public
  discoverability is **not** suppressed. Under “Item Discovery”, verify that
  “Hide this item from search results” is **not** checked.
* Verify that the "Item Access" setting is set to "Collection staff only".
* Verify that no "Assign special access" options are configured for the collection.

11.2.2) On the item:

* Go to the item detail page and verify that the item is published. If it
  is not yet published, left-click the “Publish” button and verify that a
  success notification is displayed.
* Left-click the “Edit” button to go to the “Edit Media Object > Access
  Control” page.
* On the access control page, verify that “Disable parent permissions” is
  **not** checked, so the item inherits discoverability from the collection.
* Verify that no "Assign special access" options are configured for the item.
* Left-click “Save” if any changes were made.

11.2.3) Return to the item detail page and verify that:

* The item metadata (title, description, etc.) is visible.
* The item is published and appears in browse/search results when logged
  in as an authorized user.

11.3) On the item detail page, verify that the media player is visible and that
the item can be streamed when logged in as an authorized user.

11.4) In a private/incognito browser window (not logged in and not connected to
VPN), go to

<https://av-test.lib.umd.edu/catalog>

Verify that the browse page is displayed and that you are **not** logged in.

11.5) In the same private/incognito window, search for the title of the
restricted item identified in step 11.2. Verify that the item appears in the
browse/search results.

11.6) In the private/incognito window, go to the item detail URL for the
restricted item.

11.7) Verify that:

* The item metadata (title, description, etc.) is displayed.
* A "Playback Restricted" panel or equivalent restricted playback message is
  displayed in place of the media player.

### 12) Item-Level Override Restricts Access

This section verifies that item-level override can restrict discoverability
within a publicly discoverable standard (non *Course Reserves*) collection.

12.1) Reuse the same published item from section 11. From the item detail page,
left-click the “Edit” button to go to the “Edit Media Object > Access Control”
page.

12.2) On the access control page:

* Check “Disable parent permissions”, then left-click “Save” at the bottom of
  the page.
* After saving, verify that the “Item Discovery” and “Item Access” edit options
  are visible.
* Under “Item Discovery”, verify that “Hide this item from search results” is
  checked. If it is not checked, check it and left-click “Save”.
* Under “Item Access”, set the access to “Collection staff only” and left-click
  “Save”. The expected results below depend on this: hiding an item does not
  take away access that Item Access grants, so it is the “Collection staff
  only” setting that refuses the anonymous user in step 12.5.
* Verify that no UMD IP Manager or other special access are configured on the item.

12.3) In a private/incognito browser window (not logged in and not connected to
VPN), go to

<https://av-test.lib.umd.edu/catalog>

Verify that the browse page is displayed and that you are **not** logged in.

12.4) In the same private/incognito window, search for the title of the item.
Verify that the item does **not** appear in the browse/search results.

12.5) In the private/incognito window, go directly to the item detail URL.

Verify that:

* The item detail page is not viewable by the anonymous user. You should see a
  "Restricted Content" message and a 401 Unauthorized response code.
* The item metadata (title, description, etc.) is **not** displayed.

12.6) Verify that hiding the item does **not** revoke an access token.

Hiding an item controls only its discoverability; users who were granted access
explicitly must still be able to reach it.

12.6.1) In the administrator window, go to the item detail page and left-click
the "Access Tokens" button. Create a new access token for the item with
streaming enabled, and copy the generated access token URL.

12.6.2) In a new private/incognito window, paste the access token URL.

Verify that:

* The item detail page **is** displayed, even though the item is hidden.
* The item metadata (title, description, etc.) is displayed.
* The media player is displayed, and the item can be streamed successfully.

12.7) Verify that hiding the item does **not** revoke "Assign special access".

12.7.1) In the administrator window, left-click the "Edit" button for the item,
then go to the "Access Control" page. Under "Assign special access", add a
specific Avalon user (for example, a test account you can log in as) and
left-click "Save".

12.7.2) In a new private/incognito window, log in to Avalon via CAS as that
user, then go directly to the item detail URL.

Verify that:

* The item detail page **is** displayed, even though the item is hidden.
* The item still does **not** appear in browse/search results for that user.

12.8) Verify that hiding does **not** override Item Access.

The item used above has Item Access "Collection staff only", which is why the
anonymous user was refused in step 12.5. Hiding an item removes it from
browse/search and withdraws the metadata view a published item otherwise grants
to everyone, but it never takes away access that Item Access itself grants.

12.8.1) In the administrator window, remove the special access user added in
step 12.7.1. On the "Access Control" page, set "Item Access" to "Available to
the general public", leave "Hide this item from search results" checked, and
left-click "Save".

12.8.2) In a private/incognito window (not logged in), search for the title of
the item, then go directly to the item detail URL.

Verify that:

* The item still does **not** appear in the browse/search results.
* The item detail page **is** viewable, and the item metadata (title,
  description, etc.) is displayed.
* The media player is displayed, and the item can be streamed successfully.

12.8.3) In the administrator window, set "Item Access" to "Logged in users
only" and left-click "Save". In a private/incognito window (not logged in), go
directly to the item detail URL.

Verify that:

* The item detail page is **not** viewable. You should see a "Restricted
  Content" message and a 401 Unauthorized response code.

12.8.4) In the same private/incognito window, log in to Avalon via CAS as an
ordinary user (one who is not staff on the collection), then go directly to the
item detail URL.

Verify that:

* The item detail page **is** viewable, and the item metadata is displayed.
* The item still does **not** appear in the browse/search results for that user.

12.9) Verify that the same holds when Item Access is set on the collection.

12.9.1) In the administrator window, edit the item's "Access Control" page,
uncheck "Disable parent permissions", and left-click "Save". Then go to the
collection's edit page and set the collection's "Item Access" to "Available to
the general public" and "Item Discovery" to hidden, and save.

12.9.2) In a private/incognito window (not logged in), search for the title of
the item, then go directly to the item detail URL.

Verify that:

* The item does **not** appear in the browse/search results.
* The item detail page **is** viewable, and the item can be streamed
  successfully.

### 13) UMD IP Manager Group-Based Access

> **Note:** Since the Avalon pre-production environments are not accessible
> outside the UMD network, we will test IP-based access control by first
> restricting access to a more restrictive IP Manager group (for example, *The
> Jim Henson Works* IP Manager group, which is limited to a small set of
> McKeldin public access computers) to verify that access is correctly
> **blocked**. We will then expand access to the broader *UMD College Park
> campus and VPN* group to verify that access is **granted** as expected.

13.1) Log in to Avalon via CAS as an administrator. From the navigation bar,
select "Manage | Manage Content". The page with units and collections will be
displayed.

13.2) Create or identify a collection that will be used to test IP-based access
control (for example, a collection intended for campus/VPN-only streaming).

13.3) On the collection detail page, under the "Assign special access" section,
left-click the UMD IP Manager dropdown and select *The Jim Henson Works* group.
Left-click the "**Add**" button next to the dropdown to save the changes.

13.4) Create or identify a published item in the collection. If reusing the item
from section 12, ensure that the changes for step 12.2 (disabling parent
permissions and hiding the item from search results) are reverted so that the
item inherits discoverability from the collection.

13.5) In a private/incognito browser window (not logged in and not connected to
VPN), go to

<https://av-test.lib.umd.edu/catalog>

Search for the title of the item created/identified in step 13.4 and verify that
the item appears in the browse/search results.

13.6) In the same private/incognito window, go to the item detail URL.

13.6.1) If you're on campus (McKeldin Library), and **not** connected to VPN,
verify that:

* The item metadata (title, description, etc.) is displayed.
* The media player is displayed, and the item can be streamed successfully.

13.6.2) If you're off/on campus, and connected to VPN, verify that:

* The item metadata (title, description, etc.) is displayed.
* A "Playback Restricted" panel or equivalent restricted playback message is
  displayed in place of the media player.

13.7) Optionally, if doing this test after a major upgrade, physically go the
McKeldin Library public access computers and test access anonymously from a
computer in the *The Jim Henson Works* IP Manager group.

Verify that:

* The item metadata (title, description, etc.) is displayed.
* The media player is displayed, and the item can be streamed successfully.

13.8) Change the IP Manager group for the collection

13.8.1) On the collection detail page, under the "Assign special access"
section, left-click the UMD IP Manager dropdown and select *UMD College Park
campus and VPN* group. Left-click the "**Add**" button next to the dropdown to
save the changes.

13.8.2) On the collection detail page, under the "Assign special access"
section, left-click the "X" next to the *The Jim Henson Works* group to remove it.

13.9) In the same private/incognito window, go to the item detail URL.

13.9.1) If you're on campus, or connected to VPN, verify that:

* The item metadata (title, description, etc.) is displayed.
* The media player is displayed, and the item can be streamed successfully.

### 14) Course Reserves Items Not Discoverable to Public Users

This section verifies that items in a Course Reserves collection (a collection
belonging to the "Streaming Reserves" unit) are not publicly discoverable.
The Course Reserves collection does not propagate public discoverability to
its items, so anonymous users should not find those items via browse or search.

14.1) Log in to Avalon via CAS as an administrator. From the navigation bar,
select "Manage | Manage Content". The page with units and collections will be
displayed.

14.2) Find the Course Reserves (usually named the *Digitized Items*) collection
under the collections section. If it does not exist, create a new course
reserves collection by following the steps in section 6.2

* Go to the collection detail page and confirm the collection belongs to the
  "Streaming Reserves" unit.
* Left-click the "Edit" button. On the collection access control/settings
  page, verify that no UMD IP Manager groups are configured on the collection.

14.3) Find or create a published item in the Course Reserves collection. If
creating a new item, follow the steps in section 4 to create and publish the
item.

* Go to the item detail page.
* Left-click the "Edit" button to go to the "Edit Media Object > Access
  Control" page.
* Verify that "Disable parent permissions" is **not** checked, so the item
  inherits access settings from the collection.
* Left-click "Save" if any changes were made.

14.4) In a private/incognito browser window (not logged in and not connected to
VPN), go to

<https://av-test.lib.umd.edu/catalog>

Verify that the browse page is displayed and that you are **not** logged in.

14.5) In the same private/incognito window, search for the title of the Course
Reserves item identified in step 14.3. Verify that the item does **not** appear
in the browse/search results.

14.6) In the private/incognito window, go directly to the item detail URL for
the Course Reserves item.

Verify that:

* The item detail page is not viewable by the anonymous user. You should see a
  "Restricted Content" message and a 401 Unauthorized response code.
* The item metadata (title, description, etc.) is **not** displayed.

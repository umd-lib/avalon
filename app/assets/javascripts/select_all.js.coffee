# Copyright 2011-2023, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

# Mark each item on page as bookmarks when 'Select All' is clicked
$("#bookmarks_selectall").on "change", (e) ->
  if @checked
    # UMD Customization
    allowed = Number($('#bookmarks_selectall')[0].dataset.limit) - Number($('[data-role=bookmark-counter]').text());
    $("label.toggle-bookmark:not(.checked) input.toggle-bookmark:lt(" + allowed + ")").click()
    if allowed < $("label.toggle-bookmark:not(.checked) input.toggle-bookmark").length
      alert("Could not select all items. Max selection limit reached: " + $('#bookmarks_selectall')[0].dataset.limit)
      $('#bookmarks_selectall')[0].checked = false
    # End UMD Customization
  else
    $("label.toggle-bookmark.checked input.toggle-bookmark").click()
  return

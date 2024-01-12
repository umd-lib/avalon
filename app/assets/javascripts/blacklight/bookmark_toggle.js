(function($) {
    //change form submit toggle to checkbox
    Blacklight.doBookmarkToggleBehavior = function() {
      if (typeof Blacklight.do_bookmark_toggle_behavior == 'function') {
        console.warn("do_bookmark_toggle_behavior is deprecated. Use doBookmarkToggleBehavior instead.");
        return Blacklight.do_bookmark_toggle_behavior();
      }
      $(Blacklight.doBookmarkToggleBehavior.selector).blCheckboxSubmit({
         // cssClass is added to elements added, plus used for id base
         cssClass: 'toggle-bookmark',
         success: function(checked, response) {
           if (response.bookmarks) {
                $('[data-role=bookmark-counter]').text(response.bookmarks.count);
                Blacklight.toggleBookmarkCheckboxDisabled();
           }
         }
      });

    };
    Blacklight.doBookmarkToggleBehavior.selector = 'form.bookmark-toggle';

    Blacklight.toggleBookmarkCheckboxDisabled = function() {
        if ( Number($('[data-role=bookmark-counter]').text()) >= Number($('#bookmarks_selectall')[0].dataset.limit) ) {
            message = "Max selection limit reached: " + $('#bookmarks_selectall')[0].dataset.limit;
            $('#bookmarks_selectall').not('.checked').attr('disabled', true);
            $('#bookmarks_selectall').not('.checked').attr('data-toggle', "tooltip");
            $('#bookmarks_selectall').not('.checked').attr('data-placement', "right");
            $('#bookmarks_selectall').not('.checked').attr('title', message);
            $('#bookmarks_selectall').not('.checked').bstooltip()
            $('label.toggle-bookmark').not('.checked').children('input').attr('disabled', true);
            $('label.toggle-bookmark').not('.checked').children('input').attr('data-toggle', "tooltip");
            $('label.toggle-bookmark').not('.checked').children('input').attr('data-placement', "right");
            $('label.toggle-bookmark').not('.checked').children('input').attr('title', message);
            $('label.toggle-bookmark').not('.checked').children('input').bstooltip()
            
        } else {
            $('#bookmarks_selectall').not('.checked').removeAttr('disabled');
            $('#bookmarks_selectall').not('.checked').removeAttr('title');
            $('#bookmarks_selectall').not('.checked').bstooltip('dispose')
            $('label.toggle-bookmark').not('.checked').children('input').removeAttr('disabled');
            $('label.toggle-bookmark').not('.checked').children('input').removeAttr('title');
            $('label.toggle-bookmark').not('.checked').children('input').bstooltip('dispose')
        }
    }

Blacklight.onLoad(function() {
  if ($('#bookmarks_selectall')[0] &&
      Number($('[data-role=bookmark-counter]').text() >= Number($('#bookmarks_selectall')[0].dataset.limit))) {
    Blacklight.toggleBookmarkCheckboxDisabled();
  }
});


})(jQuery);

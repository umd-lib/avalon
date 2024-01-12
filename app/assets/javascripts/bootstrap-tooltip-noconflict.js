// Store bootstrap version of tooltip fn as 'bstooltip' before jquery-ui version overrides it.
$.fn.bstooltip = $.fn.tooltip.noConflict();
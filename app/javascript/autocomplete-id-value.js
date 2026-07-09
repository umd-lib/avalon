// UMD Customization 
/**
 * This code ensures that when a user selects an option from the autocomplete
 * dropdown, the hidden input field (which holds the actual value to be
 * submitted) is updated with the correct id, while the visible input field
 * (which shows the user-friendly display text) is updated with the
 * corresponding display value. This is important for maintaining data integrity
 * and ensuring that the correct values are submitted in forms that use
 * autocomplete functionality.
 */
document.addEventListener('combobox-commit', function(event) {
  const li = event.target;
  if (!li.matches('[role="option"]')) return;

  const autoComplete = li.closest('auto-complete.typeahead');
  if (!autoComplete) return;

  const hiddenField = autoComplete.querySelector('input[type="hidden"]');
  const displayField = autoComplete.querySelector('.typeahead-input');
  if (!hiddenField || !displayField) return;

  hiddenField.value = li.getAttribute('data-autocomplete-value');
  displayField.value = li.textContent.trim();
});
// End UMD Customization
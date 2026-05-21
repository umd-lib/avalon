/**
 * Mount React components in Blacklight modals
 * This is necessary because Blacklight modals load their content via AJAX,
 * so we need to manually mount any React components within the modal after
 * the content is loaded.
 */
document.addEventListener('DOMContentLoaded', function () {
  const modalContainer = document.querySelector('#blacklight-modal .modal-content');
  if (!modalContainer) return;

  // Watch for new content being inserted into the modal
  const observer = new MutationObserver((mutationsList) => {
    mutationsList.forEach((mutation) => {
      if (mutation.addedNodes.length > 0 && typeof ReactOnRails !== 'undefined') {
        ReactOnRails.reactOnRailsPageLoaded();
      }
    });
  });

  observer.observe(modalContainer, { childList: true, subtree: true });
});

// UMD custom component for displaying the Aeon
// "Request from Special Collections" button
import React from 'react';

const AeonRequestForm = ({ aeonRequest }) => {
  return (
    <form
      action={aeonRequest.aeonURL}
      id="aeon_request_sub"
      target="aeon_request"
      method="post"
    >
      <input type="hidden" name="ItemTitle" value={aeonRequest.itemTitle} />
      <input type="hidden" name="ItemDate" value={aeonRequest.itemDate} />
      <input type="hidden" name="Location" value={aeonRequest.location} />
      <input type="hidden" name="CallNumber" value={aeonRequest.callNumber} />
      <input type="hidden" name="ReferenceNumber" value={aeonRequest.referenceNumber} />

      <button type="submit" className="request-and-handle-button" title="Request from Special Collections">
        <span>
          <svg title="new window icon" id="icon_new_window" aria-hidden="true" data-name="new-window-icon" viewBox="0 0 13 9" xmlns="http://www.w3.org/2000/svg">
            <path class="cls-1" d="M6.67,2.28H1.28S3.63,0,3.63,0h4.49s2.29,0,2.29,0h0s0,2.28,0,2.28h0v4.49s-2.29,2.35-2.29,2.35V3.95S1.55,10.67,1.55,10.67l-1.55-1.55L6.67,2.28Z">
            </path>
          </svg>
        </span>
        Request This Item
      </button>
    </form>
  );
};

export default AeonRequestForm;

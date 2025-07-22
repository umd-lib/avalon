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

      <button type="submit" className="btn btn-outline" title="Request from Special Collections">
        Request from Special Collections
      </button>
    </form>
  );
};

export default AeonRequestForm;

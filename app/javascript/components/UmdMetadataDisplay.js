/**
 * Component to display additional UMD specific metadata for a media object
 * Additonal metadata fields:
 *  - Handle URL with a copy button
*/

import React, { useState } from 'react';
import PropTypes from 'prop-types';

const UmdMetadataDisplay = ({ handleUrl }) => {
  const [copySuccess, setCopySuccess] = useState('');


  return (
    <div className="umd-metadata-display">
      {handleUrl && (
        <div className="handle-url">
          <dt>Handle Url</dt>
          <dd>{handleUrl}</dd>
        </div>
      )}
    </div>
  );
}

UmdMetadataDisplay.propTypes = {
  handleUrl: PropTypes.string,
}

export default UmdMetadataDisplay;
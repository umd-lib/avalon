import React from 'react';
import PropTypes from 'prop-types';

const UmdCopyHandleUrlButton = ({ handleUrl = '' }) => {

  const copyToClipboard = () => {
    const textarea = document.createElement('textarea');
    textarea.value = handleUrl;
    textarea.style.position = 'fixed';  // prevent scrolling to bottom
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    const successful = document.execCommand('copy');
    document.body.removeChild(textarea);
  };

  return (
    <button className="btn btn-outline mr-1 text-nowrap" type="button" onClick={copyToClipboard}>
    Copy Handle Url
    </button>
  );
}

UmdCopyHandleUrlButton.propTypes = {
  handleUrl: PropTypes.string.isRequired,
};

export default UmdCopyHandleUrlButton;
import React from 'react';

// UMD custom component for displaying a list of master file downloads
// as a tab in the MediaObjectRamp sidebar.
const UmdMasterFileDownloadsTab = ({ masterFiles }) => {
  const renderMasterFileDownload = (masterFile) => {
    return (
      <li key={masterFile.id}>
        <a href={masterFile.url}>{masterFile.fileName}</a>
      </li>
    );
  };

  return (
    <ul>
      {masterFiles.downloads.map((download) => renderMasterFileDownload(download))}
    </ul>
  );
};

export default UmdMasterFileDownloadsTab;
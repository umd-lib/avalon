import React from 'react';

// UMD custom component for displaying a list of master file downloads
// as a tab in the MediaObjectRamp sidebar.
const UmdMasterFiles = ({ masterFiles }) => {
  const renderMasterFileDownload = (masterFile) => {
    return (
      <dd key={masterFile.id}>
        <a href={masterFile.url}>{masterFile.fileName}</a>
      </dd>
    );
  };

  return (
    // Using "ramp--supplemental-files" CSS styles to maintain consistency
    // with the Avalon "Supplemental File" styling in the same tab.
    <div className='ramp--supplemental-files'>
      <div className='ramp--supplemental-files-display-content'>
        <h4>Media Files</h4>
        <dl>
          {masterFiles.downloads.map((download) => renderMasterFileDownload(download))}
        </dl>
      </div>
    </div>
  );
};

export default UmdMasterFiles;

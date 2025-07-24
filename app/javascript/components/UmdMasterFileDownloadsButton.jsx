import React from 'react';

// UMD custom component for displaying a "Downloads" button that opens
// a modal dialog
const UmdMasterFileDownloadsButton = ({ masterFiles }) => {
  return (
    <>
      {/* Download Button */}
      <button
        type="button"
        className="btn btn-outline mr-1 text-nowrap"
        id="download-button"
        data-toggle="modal"
        data-target="#downloadModal"
      >
        <i className="fa fa-download" style={{ color: '#2a5459' }}></i>
        Download
      </button>

      {/* Modal */}
      <div
        className="modal fade"
        id="downloadModal"
        tabIndex="-1"
        role="dialog"
        aria-labelledby="exampleModalLabel"
        aria-hidden="true"
        style={{ display: 'none' }}
      >
        <div className="modal-dialog" role="document">
          <div className="modal-content">
            <div className="modal-header">
              <h5 className="modal-title" id="downloadModalLabel">
                Download
              </h5>
            </div>
            <div className="modal-body">
              <ul>
                {masterFiles.downloads.map((masterFile) => (
                <li key={masterFile.id}>
                  <a href={masterFile.url}>{masterFile.fileName}</a>
                </li>
                ))}
              </ul>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" data-dismiss="modal">
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

export default UmdMasterFileDownloadsButton;
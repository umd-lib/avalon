/**
 * Component to filter facet values for Course Name facet
*/

import React, { useState, useRef } from 'react';

const UMDFacetFilter = ({ baseUrl, contains }) => {
  const [value, setValue] = useState(contains || '');
  const buttonRef = useRef(null);

  const handleChange = (e) => setValue(e.target.value);

  const buildUrl = () => {
    if (!value.trim()) return '#';
    const url = new URL(baseUrl, window.location.origin);
    url.searchParams.set('contains', value.trim());
    return url.toString();
  };

  const clearUrl = () => {
    const url = new URL(baseUrl, window.location.origin);
    url.searchParams.delete('contains');
    return url.toString();
  };

  const handleEnter = (e) => {
    if (e.key === 'Enter' && value.trim() && buttonRef.current) {
      buttonRef.current.click();
    }
  };

  const handleClear = (e) => {
    if (!contains) {
      // If original page has no 'contains', prevent server request
      e.preventDefault();
      e.stopPropagation();
    }
    setValue('');
  };

  const isDisabled = !value.trim();

  return (
    <div className="facet-filter mb-3 d-flex align-items-center">
      <input
        type="text"
        className="form-control mr-2"
        placeholder="Filter values..."
        value={value}
        onChange={handleChange}
        onKeyDown={handleEnter}
      />
      <a
        href={buildUrl()}
        className={`btn btn-primary mr-2 ${isDisabled ? 'disabled' : ''}`}
        ref={buttonRef}
        data-blacklight-modal="preserve"
        onClick={(e) => {
          if (isDisabled) e.preventDefault();
        }}
      >
        Filter
      </a>
      <a
        href={clearUrl()}
        className={`btn btn-danger ${isDisabled ? 'disabled' : ''}`}
        data-blacklight-modal="preserve"
        onClick={handleClear}
      >
        Clear
      </a>
    </div>
  );
};

export default UMDFacetFilter;

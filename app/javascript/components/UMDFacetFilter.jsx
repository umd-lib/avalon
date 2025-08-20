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

  const handleEnter = (e) => {
    if (e.key === 'Enter' && value.trim() && buttonRef.current) {
      buttonRef.current.click();
    }
  };

  const isDisabled = !value.trim();

  return (
    <div className="facet-filter mb-3 d-flex">
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
        ref={buttonRef}
        className={`btn btn-primary ${isDisabled ? 'disabled' : ''}`}
        onClick={(e) => { if (isDisabled) e.preventDefault(); }}
        data-blacklight-modal="preserve"
      >
        Filter
      </a>
    </div>
  );
};

export default UMDFacetFilter;

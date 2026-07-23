/*
 * Copyright 2011-2026, The Trustees of Indiana University and Northwestern
 *   University.  Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed
 *   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 *   CONDITIONS OF ANY KIND, either express or implied. See the License for the
 *   specific language governing permissions and limitations under the License.
 * ---  END LICENSE_HEADER BLOCK  ---
*/

import { useState, useCallback, useEffect, useRef } from 'react';
import GenericTable from './GenericTable';

// TranscriptionRequest statuses that are still in flight. AWS Transcribe
// reports no numeric progress, so unlike EncodingJobsTable this table only
// polls for status changes, not a progress percentage.
const ACTIVE_STATUSES = ['pending', 'submitted', 'in_progress'];

/**
 * Render a table displaying transcription request records.
 * @param {Object} props
 * @param {String} props.url API endpoint URL for fetching transcription request data
 * @param {String} props.progressUrl API endpoint URL for fetching status updates
 */
const TranscriptionRequestsTable = ({ url, progressUrl }) => {
  const [statusData, setStatusData] = useState({});
  const [currentRequests, setCurrentRequests] = useState([]);
  const timeoutRef = useRef(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  const fetchStatusUpdates = useCallback(async (ids) => {
    if (!ids.length) return null;

    try {
      const response = await fetch(progressUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': query('meta[name="csrf-token"]')?.getAttribute('content'),
        },
        body: JSON.stringify({ ids })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      return await response.json();
    } catch (error) {
      console.error('Error fetching transcription status updates:', error);
      return null;
    }
  }, [progressUrl]);

  // Poll every 10 seconds while any visible request is still active.
  useEffect(() => {
    const activeIds = currentRequests
      .filter(item => ACTIVE_STATUSES.includes((statusData[item.transcription_request_id]?.status || item.status || '').toLowerCase()))
      .map(item => item.transcription_request_id);

    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    if (!activeIds.length) return undefined;

    const poll = async () => {
      const data = await fetchStatusUpdates(activeIds);
      if (data && mountedRef.current) {
        setStatusData(prev => ({ ...prev, ...data }));

        const stillActive = Object.values(data).some(item => ACTIVE_STATUSES.includes((item.status || '').toLowerCase()));
        if (stillActive) {
          timeoutRef.current = setTimeout(poll, 10000);
        }
      }
    };

    timeoutRef.current = setTimeout(poll, 10000);
    return () => { if (timeoutRef.current) clearTimeout(timeoutRef.current); };
  }, [currentRequests, fetchStatusUpdates, statusData]);

  const tableConfig = {
    tableType: 'transcription_request',
    containerClass: 'transcription_requests-table-container',
    testId: 'transcription_requests-table',
    hasTagFilter: false,

    pageSizeOptions: [10, 20, 50, 100],
    initPageSize: 20,

    initialSort: { columnKey: 'created', dataType: 'date', direction: 'desc', column: 5 },
    searchableFields: ['status', 'id', 'provider', 'master_file', 'media_object'],

    columns: [
      { key: 'status', label: 'Status', sortable: true, dataType: 'string', width: '10%' },
      { key: 'id', label: 'ID', sortable: true, dataType: 'number', width: '5%' },
      { key: 'provider', label: 'Provider', sortable: true, dataType: 'string', width: '10%' },
      { key: 'master_file', label: 'MasterFile', sortable: true, dataType: 'string', width: '15%' },
      { key: 'media_object', label: 'MediaObject', sortable: true, dataType: 'string', width: '15%' },
      { key: 'created', label: 'Created', sortable: true, dataType: 'date', width: '15%' },
      { key: 'actions', label: '', sortable: false, width: '20%' }
    ],

    // Data parsing function to extract data from Rails API response
    parseDataRow: useCallback((row, index) => {
      const parser = new DOMParser();
      const statusDoc = parser.parseFromString(row[0], 'text/html');
      const idDoc = parser.parseFromString(row[1], 'text/html');
      const masterFileDoc = parser.parseFromString(row[3], 'text/html');
      const mediaObjectDoc = parser.parseFromString(row[4], 'text/html');

      const statusSpan = statusDoc.querySelector('span[data-transcription-request-id]');
      const transcription_request_id = statusSpan ? statusSpan.getAttribute('data-transcription-request-id') : null;

      return {
        transcription_request_id,
        status: statusDoc.querySelector('span').textContent,
        id_html: row[1], id: idDoc ? idDoc.querySelector('a').textContent : index,
        provider: row[2],
        masterfile_html: row[3], master_file: masterFileDoc.querySelector('a')?.textContent || '',
        mediaobject_html: row[4], media_object: mediaObjectDoc.querySelector('a')?.textContent || '',
        created_html: row[5], created: new Date(row[5]),
        actions_html: row[6]
      };
    }, []),

    onDataParsed: (parsedData) => {
      setCurrentRequests(parsedData);
    },

    // Cell rendering function for each column key
    renderCell: useCallback((item, columnKey) => {
      const updated = statusData[item.transcription_request_id];

      switch (columnKey) {
        case 'status':
          return updated ? updated.status : item.status;
        case 'id':
          return <div dangerouslySetInnerHTML={{ __html: item.id_html }} />;
        case 'provider':
          return item.provider;
        case 'master_file':
          return <span dangerouslySetInnerHTML={{ __html: item.masterfile_html }} />;
        case 'media_object':
          return <span dangerouslySetInnerHTML={{ __html: item.mediaobject_html }} />;
        case 'created':
          return item.created_html;
        case 'actions':
          // Rendered once from the initial server response — re-fetch the
          // page after acting to see the resulting state reflected here.
          return <div dangerouslySetInnerHTML={{ __html: item.actions_html }} />;
        default:
          return item[columnKey];
      }
    }, [statusData])
  };

  return <GenericTable config={tableConfig} url={url} tags={[]} />;
};

export default TranscriptionRequestsTable;

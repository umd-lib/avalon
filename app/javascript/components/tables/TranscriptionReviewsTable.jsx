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

import { useCallback } from 'react';
import GenericTable from './GenericTable';

/**
 * Render a table of machine-generated captions/transcripts awaiting human
 * review. Unlike TranscriptionRequestsTable, review status here only
 * changes through the reviewer's own Approve/Reject action on this same
 * page (a full page reload via the resulting redirect), not an external
 * async process — so there's no progress-polling to do.
 * @param {Object} props
 * @param {String} props.url API endpoint URL for fetching pending-review data
 */
const TranscriptionReviewsTable = ({ url }) => {
  const tableConfig = {
    tableType: 'transcription_review',
    containerClass: 'transcription_reviews-table-container',
    testId: 'transcription_reviews-table',
    hasTagFilter: false,

    pageSizeOptions: [10, 20, 50, 100],
    initPageSize: 20,

    initialSort: { columnKey: 'created', dataType: 'date', direction: 'desc', column: 4 },
    searchableFields: ['type', 'id', 'master_file', 'media_object', 'language'],

    columns: [
      { key: 'type', label: 'Type', sortable: true, dataType: 'string', width: '10%' },
      { key: 'id', label: 'ID', sortable: true, dataType: 'number', width: '5%' },
      { key: 'master_file', label: 'MasterFile', sortable: true, dataType: 'string', width: '15%' },
      { key: 'media_object', label: 'MediaObject', sortable: true, dataType: 'string', width: '15%' },
      { key: 'language', label: 'Language', sortable: true, dataType: 'string', width: '10%' },
      { key: 'created', label: 'Created', sortable: true, dataType: 'date', width: '15%' },
      { key: 'actions', label: '', sortable: false, width: '20%' }
    ],

    // Data parsing function to extract data from Rails API response
    parseDataRow: useCallback((row, index) => {
      const parser = new DOMParser();
      const masterFileDoc = parser.parseFromString(row[2], 'text/html');
      const mediaObjectDoc = parser.parseFromString(row[3], 'text/html');

      return {
        type: row[0],
        id: row[1],
        masterfile_html: row[2], master_file: masterFileDoc.querySelector('a')?.textContent || '',
        mediaobject_html: row[3], media_object: mediaObjectDoc.querySelector('a')?.textContent || '',
        language: row[4],
        created_html: row[5], created: new Date(row[5]),
        actions_html: row[6]
      };
    }, []),

    // Cell rendering function for each column key
    renderCell: useCallback((item, columnKey) => {
      switch (columnKey) {
        case 'type':
          return item.type;
        case 'id':
          return item.id;
        case 'master_file':
          return <span dangerouslySetInnerHTML={{ __html: item.masterfile_html }} />;
        case 'media_object':
          return <span dangerouslySetInnerHTML={{ __html: item.mediaobject_html }} />;
        case 'language':
          return item.language;
        case 'created':
          return item.created_html;
        case 'actions':
          // Rendered once from the initial server response — re-fetch the
          // page after acting to see the resulting state reflected here.
          return <div dangerouslySetInnerHTML={{ __html: item.actions_html }} />;
        default:
          return item[columnKey];
      }
    }, [])
  };

  return <GenericTable config={tableConfig} url={url} tags={[]} />;
};

export default TranscriptionReviewsTable;

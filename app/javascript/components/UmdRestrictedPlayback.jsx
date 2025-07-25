/** 
 * UMD Custom component for displaying restricted playback message when
 * a media object is not available for playback.
 */
import React from 'react';
import PropTypes from 'prop-types';

const UmdRestrictedPlayback = ({ jim_hension_collection = '' }) => {
    
    return (
            <div className="restricted-video">
                <div className="restricted-video-message">
                    <h3>Playback Restricted</h3>
                    { jim_hension_collection ? (
                    <>
                        Digital videos from <i>{ jim_hension_collection }</i> are available for viewing only from public computers at these locations:
                        <ul>
                        <li><a href="https://www.lib.umd.edu/mspal">Michelle Smith Performing Arts Library</a></li>
                        <li><a href="https://www.lib.umd.edu/hornbake">Hornbake Library</a></li>
                        <li><a href="https://www.lib.umd.edu/mckeldin">McKeldin Library</a></li>
                        </ul>
                    </>
                    ) : (
                    <>
                        This content is available for streaming only at the University of Maryland's College Park campus or through a <a
                        href="https://digital.lib.umd.edu/help_video#vpn">VPN connection</a> with the Tunnel All gateway by choosing the option from Change Gateway dropdown menu. This content may be accessed from public
                        computers at any of the UMD Libraries on the College Park campus.
                        <br />
                        <br />
                    </>
                    )}
                    <span>Questions? <a href="https://www.lib.umd.edu/digital/contact/digital-feedback">Contact Us</a></span>
                </div>
            </div>
    );
}

UmdRestrictedPlayback.propTypes = {
    jim_hension_collection: PropTypes.string
};

export default UmdRestrictedPlayback;
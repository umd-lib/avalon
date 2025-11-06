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
                        Digital videos from <i>{ jim_hension_collection }</i> collection at the University of Maryland
                        are currently accessible by request only and for viewing within specific UMD Libraries branches.
                        To request a link to view a video, please contact Special Collections in Performing Arts at <a
                        href="mailto:scpa@umd.edu">scpa@umd.edu</a>.
                        <br />
                        <br />
                    </>
                    ) : (
                    <>
                        This content is available for streaming only at the University of Maryland's College Park campus or through a <a
                        href="https://digital.lib.umd.edu/help_video#vpn">VPN connection</a> with the Tunnel All gateway by choosing the option from Change Gateway dropdown menu.
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
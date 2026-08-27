# Copyright 2011-2026, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

# UMD Customization
# Custom proxy for Course Reserves to perform lease checks directly from Solr.
# The methods are copied from the main Lease model, but updated to use `attrs`.
class SpeedyAF::Proxy::Lease < SpeedyAF::Base

  # Take a supplied date and format it in iso8601 with the time portion set to 00:00:00 UTC
  # @param [Date, Time, String] a date or time object or a string that DateTime can parts_with_order
  # @return [String] supplied date and time with the passed date and time portion set to 00:00:00 UTC time in the iso8601 format
  def start_of_day(time)
    DateTime.parse(time.to_s).utc.to_datetime.beginning_of_day
  end

  # Take a supplied date and format it in iso8601 with the time portion set to 11:59:59 UTC
  # @param [Date, Time, String] a date or time object or a string that DateTime can parts_with_order
  # @return [String] supplied date and time with the passed date and time portion set to 11:59:59 UTC time in the iso8601 format
  def end_of_day(time)
    DateTime.parse(time.to_s).utc.to_datetime.end_of_day
  end

  # Determines if the lease is currently active (today is between the begin and end time)
  # @return [Boolean] returns true if the lease is active
  def lease_is_active?
    return false if attrs[:begin_time].blank? || attrs[:end_time].blank?
    start_of_day(Date.today) >= attrs[:begin_time] && end_of_day(Date.today) <= attrs[:end_time]
  end
end
# End UMD Customization

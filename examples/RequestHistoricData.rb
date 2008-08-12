#!/usr/bin/env ruby -w
#
# Copyright (C) 2007-8 Paul Legato.
#
# This library is free software; you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 2.1 of the
# License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA
#

$:.push(File.dirname(__FILE__) + "/../")

# IB-Ruby libraries
require 'ib'
require 'datatypes'
require 'symbols/futures'

# Gems
require 'rubygems'
require 'duration'
require 'getopt/long'



if opt["help"]
  puts <<ENDHELP

** RequestHistoricData.rb - Copyright (C) 2007-8 Paul Legato.

 This library is free software; you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as
 published by the Free Software Foundation; either version 2.1 of the
 License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 02110-1301 USA

**** At the moment, the program is hardcoded to return Euro FX futures data from Globex.

Options:

--end is is the last time we want data for. The default is now.


--duration is how much historic data we want, in seconds, before --end's time.
  The default is 1 hour.


--what determines what the data will be comprised of. This can be "trades", "midpoint", "bid", or "asked".
  The default is "trades".


--barsize determines how long each bar will be.

Bar size values from the IB documentation:

 1 = 1 sec
 2 = 5 sec
 3 = 15 sec
 4 = 30 sec
 5 = 1 minute
 6 = 2 minutes
 7 = 5 minutes
 8 = 15 minutes
 9 = 30 minutes
 10 = 1 hour
 11 = 1 day

 Values less than 4 do not appear to actually work; they are rejected by the server.
 The default is 7.

--regularhours :
 If --regularhours is set to 0, all data available during the time
 span requested is returned, even data bars covering time
 intervals where the market in question was illiquid. If useRTH
 has a non-zero value, only data within the "Regular Trading
 Hours" of the product in question is returned, even if the time
 span requested falls partially or completely outside of them.

 The default is 1.


--dateformat : a --dateformat of 1 will cause the dates in the returned
 messages with the historic data to be in a text format, like
 "20050307 11:32:16". If you set :format_date to 2 instead, you
 will get an offset in seconds from the beginning of 1970, which
 is the same format as the UNIX epoch time.

 The default is 1 (UNIX time.)


ENDHELP

  exit

end

### Parameters

# DURATION is how much historic data we want, in seconds, before END_DATE_TIME.
# (The 'duration' gem gives us methods like #hour on integers.)
DURATION = opt["duration"].to_i || 1.hour


# This is the last time we want data for.
END_DATE_TIME = (opt["end"] && opt["end"].to_i) || Time.now.to_ib


# This can be :trades, :midpoint, :bid, or :asked
WHAT = (opt["what"] && opt["what"].to_sym) || :trades

# Possible bar size values:
# 1 = 1 sec
# 2 = 5 sec
# 3 = 15 sec
# 4 = 30 sec
# 5 = 1 minute
# 6 = 2 minutes
# 7 = 5 minutes
# 8 = 15 minutes
# 9 = 30 minutes
# 10 = 1 hour
# 11 = 1 day
#
# Values less than 4 do not appear to actually work; they are rejected by the server.
#
BAR_SIZE = (opt["barsize"] && opt["barsize"].to_i) || 7

# If REGULAR_HOURS_ONLY is set to 0, all data available during the time
# span requested is returned, even data bars covering time
# intervals where the market in question was illiquid. If useRTH
# has a non-zero value, only data within the "Regular Trading
# Hours" of the product in question is returned, even if the time
# span requested falls partially or completely outside of them.

REGULAR_HOURS_ONLY = (opt["regularhours"] && opt["regularhours"].to_i) || 1

# Using a DATE_FORMAT of 1 will cause the dates in the returned
# messages with the historic data to be in a text format, like
# "20050307 11:32:16". If you set :format_date to 2 instead, you
# will get an offset in seconds from the beginning of 1970, which
# is the same format as the UNIX epoch time.

DATE_FORMAT = (opt["dateformat"] && opt["dateformat"].to_i) || 1


#
# Definition of what we want market data for.  We have to keep track
# of what ticker id corresponds to what symbol ourselves, because the
# ticks don't include any other identifying information.
#
# The choice of ticker ids is, as far as I can tell, arbitrary.
#
# Note that as of 4/07 there is no historical data available for forex spot.
#
@market =
  {
    123 => IB::Symbols::Futures[:eur]
  }


# First, connect to IB TWS.
ib = IB::IB.new

# Uncomment this for verbose debug messages:
# IB::IBLogger.level = Logger::Severity::DEBUG

#
# Now, subscribe to HistoricalData incoming events.  The code
# passed in the block will be executed when a message of that type is
# received, with the received message as its argument. In this case,
# we just print out the data.
#
# Note that we have to look the ticker id of each incoming message
# up in local memory to figure out what it's for.
#
# (N.B. The description field is not from IB TWS. It is defined
#  locally in forex.rb, and is just arbitrary text.)

 ib.subscribe(IB::IncomingMessages::HistoricalData, lambda {|msg|
                puts @market[msg.data[:req_id]].description + ": " + msg.data[:item_count].to_s + " items:"
                msg.data[:history].each { |datum|
                  puts "   " + datum.to_s
                }
              })

# Now we actually request historical data for the symbols we're
# interested in.  TWS will respond with a HistoricalData message,
# which will be received by the code above.

@market.each_pair {|id, contract|
  msg = IB::OutgoingMessages::RequestHistoricalData.new({
                                                          :ticker_id => id,
                                                          :contract => contract,
                                                          :end_date_time => END_DATE_TIME,
                                                          :duration => DURATION, # seconds == 1 hour
                                                          :bar_size => BAR_SIZE, # 1 minute bars
                                                          :what_to_show => WHAT,
                                                          :use_RTH => REGULAR_HOURS_ONLY,
                                                          :format_date => DATE_FORMAT
                                                        })
  ib.dispatch(msg)
}


puts "Main thread going to sleep. Press ^C to quit.."
while true
  sleep 2
end

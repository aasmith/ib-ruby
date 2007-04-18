#!/usr/bin/env ruby -w
#
# Copyright (C) 2007 Paul Legato.
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

require 'ib'
require 'datatypes'
require 'symbols/futures'

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
    123 => IB::Symbols::Futures[:gbp]
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
                                                          :end_date_time => Time.now.to_ib,
                                                          :duration => "3600", # seconds == 1 hour
                                                          :bar_size => 5, # 1 minute bars
                                                          :what_to_show => :trades,
                                                          :use_RTH => 0,
                                                          :format_date => 1
                                                        })
  ib.dispatch(msg)
}

         
puts "Main thread going to sleep. Press ^C to quit.."
while true
  sleep 2
end

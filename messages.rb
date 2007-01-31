#
# Copyright (C) 2006 Blue Voodoo Magic LLC.
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
#
# EClientSocket.java uses sendMax() rather than send() for a number of these.
# It sends an EOL rather than a number if the value == Integer.MAX_VALUE (or Double.MAX_VALUE).
# These fields are initialized to this MAX_VALUE.
# This has been implemented with nils in Ruby to represent the case where an EOL should be sent.

require 'iblogger'

module IB


  ################################################################
  #### Outgoing messages
  ################################################################
  
  module OutgoingMessages
    EOL = "\0"

    class AbstractMessage
      def self.message_id
        raise Exception("AbstractMessage.message_id called - you need to override this in a subclass.")
      end

      # data is a Hash.
      def initialize(data=nil)
        @data = Datatypes::StringentHash.new(data)
      end # initialize


      # This causes the message to send itself over the server socket in server[:socket]. 
      # "server" is the @server instance variable from the IB object. You can also use this to e.g. get the server version number.
      def send(server)
        raise Exception("AbstractMessage.send called - you need to override this in a subclass.")        
      end


      protected
      
      def requireVersion(server, version)
        raise(Exception.new("TWS version >= #{version} required.")) if server[:version] < version
      end

      # Returns EOL instead of datum if datum is nil, providing the same functionality as sendMax() in the Java version,
      # which uses Double.MAX_VALUE to mean "item not set" in a variable, and replaces that with EOL on send.
      def nilFilter(datum)
        datum.nil? ? EOL : datum
      end

    end # AbstractMessage


    # Data format is { :ticker_id => int, :contract => Datatypes::Contract }
    class RequestMarketData < AbstractMessage
      def self.message_id
        1
      end

      def send(server)
        queue = [ self.class.message_id,
                  5, # message version number
                  @data[:ticker_id]
                ].concat(@data[:contract].serialize_long(server[:version]))

        queue.concat(@data[:contract].serialize_combo_legs
                     ) if server[:version] >= 8 && @data[:contract].sec_type == "BAG" # I have no idea what "BAG" means. Copied from the Java code.
        
       queue.each {|datum|
         server[:socket].syswrite(datum.to_s + "\0")
       }
      end # send
    end # RequestMarketData

    # Data format is { :ticker_id => int }
    class CancelMarketData < AbstractMessage
      def self.message_id
        2
      end
      def send(server)
        [ self.class.message_id,
          1, # message version number
          @data[:ticker_id] ].each { |datum| 
          server[:socket].syswrite(datum.to_s + "\0")
        }
      end # send
    end # CancelMarketData

    # Data format is { :order_id => int, :contract => Contract, :order => Order }
    class PlaceOrder < AbstractMessage
      def self.message_id
        3
      end

      def send(server)
        queue = [ self.class.message_id,
                  20, # version
                  @data[:order_id],
                  @data[:contract].symbol,
                  @data[:contract].sec_type,
                  @data[:contract].expiry,
                  @data[:contract].strike,
                  @data[:contract].right
                ]
        queue.push(@data[:contract].multiplier) if server[:version] >= 15
        queue.push(@data[:contract].exchange) if server[:version] >= 14
        queue.push(@data[:contract].currency) 
        queue.push(@data[:contract].local_symbol) if server[:version] >= 2

        queue.concat([
                      @data[:order].tif,
                      @data[:order].oca_group,
                      @data[:order].account,
                      @data[:order].open_close,
                      @data[:order].origin,
                      @data[:order].order_ref,
                      @data[:order].transmit
                      ])

        queue.push(@data[:contract].parent_id) if server[:version] >= 4
        
        queue.concat([
                      @data[:order].block_order,
                      @data[:order].sweep_to_fill,
                      @data[:order].display_size,
                      @data[:order].trigger_method,
                      @data[:order].ignore_rth
                     ]) if server[:version] >= 5

        queue.push(@data[:order].hidden) if server[:version] >= 7


        queue.concat(@data[:contract].serialize_combo_legs(true)) if server[:version] >= 8 && @data[:contract].sec_type.upcase == "BAG" # "BAG" is defined as a constant in EClientSocket.java, line 45

        queue.push(@data[:order].shares_allocation) if server[:version] >= 9 # EClientSocket.java says this is deprecated. No idea.
        queue.push(@data[:order].discretionary_amount) if server[:version] >= 10
        queue.push(@data[:order].good_after_time) if server[:version] >= 11
        queue.push(@data[:order].good_till_date) if server[:version] >= 12

        queue.concat([
                      @data[:order].fa_group,
                      @data[:order].fa_method,
                      @data[:order].fa_percentage,
                      @data[:order].fa_profile
                     ]) if server[:version] >= 13

        queue.concat([
                      @data[:order].short_sale_slot,
                      @data[:order].designated_location
                     ]) if server[:version] >= 18

        queue.concat([
                      @data[:order].oca_type,
                      @data[:order].rth_only,
                      @data[:order].rule_80a,
                      @data[:order].settling_firm,
                      @data[:order].all_or_none,
                      nilFilter(@data[:order].min_quantity),
                      nilFilter(@data[:order].percent_offset),
                      @data[:order].etrade_only,
                      @data[:order].firm_quote_only,
                      nilFilter(@data[:order].nbbo_price_cap),
                      nilFilter(@data[:order].auction_strategy),
                      nilFilter(@data[:order].starting_price),
                      nilFilter(@data[:order].stock_ref_price),
                      nilFilter(@data[:order].delta),

                      # Says the Java here:
                      # "// Volatility orders had specific watermark price attribs in server version 26"
                      # I have no idea what this means.

                      ((server[:version] == 26 && @data[:order].order_type.upcase == "VOL") ? EOL : @data[:order].stock_range_lower),
                      ((server[:version] == 26 && @data[:order].order_type.upcase == "VOL") ? EOL : @data[:order].stock_range_upper),
                      
                     ]) if server[:version] >= 19
        
        queue.push(@data[:order].override_percentage_constraints) if server[:version] >= 22

        # Volatility orders
        if server[:version] >= 26
          queue.concat([nilFilter(@data[:order].volatility),
                        nilFilter(@data[:order].volatility_type) ])

          if server[:version] < 28
            queue.push(@data[:order].delta_neutral_order_type.upcase == "MKT")
          else
            queue.concat([@data[:order].delta_neutral_order_type,
                          nilFilter(@data[:order].delta_neutral_aux_price)
                          ])
          end

          queue.push(@data[:order].continuous_update)
          queue.concat([
                        (@data[:order].order_type.upcase == "VOL" ? @data[:order].stock_range_lower : EOL),
                        (@data[:order].order_type.upcase == "VOL" ? @data[:order].stock_range_upper : EOL)
                       ]) if server[:version] == 26

          queue.push(@data[:order].reference_price_type)

        end # if version >= 26

        queue
      end # send

    end # PlaceOrder

    # Data format is { :id => id-to-cancel }
    class CancelOrder < AbstractMessage
      def self.message_id
        4
      end
      
      def send(server)
        [
         self.class.message_id,
         1,  # version
         @data[:id]
        ]
      end # send
    end # CancelOrder

    class RequestOpenOrders < AbstractMessage
      def self.message_id
        5
      end
      def send(server)
        [ self.class.message_id,
          1 # version
        ]
      end
    end # RequestOpenOrders

    # Data is { :subscribe => boolean, :account_code => string }
    class RequestAccountData < AbstractMessage
      def self.message_id
        6
      end
      def send(server)
        queue = [ self.class.message_id,
                  2, # version
                  @data[:subscribe]
                ]
        queue.push(@data[:account_code]) if server[:version] >= 9
        queue
      end
    end # RequestAccountData


    # data = { :filter => ExecutionFilter ]
    class RequestExecutions < AbstractMessage
      def self.message_id
        7
      end
      def send(server)
        queue = [ self.class.message_id,
                  2 # version
                ]

        queue.concat([
                      @data[:filter].client_id,
                      @data[:filter].acct_code,

                      # The Java says: 'Note that the valid format for m_time is "yyyymmdd-hh:mm:ss"'
                      @data[:filter].time,
                      @data[:filter].symbol,
                      @data[:filter].sec_type,
                      @data[:filter].exchange,
                      @data[:filter].side                      
                     ]) if server[:version] >= 9
                  
        queue
      end # send
    end # RequestExecutions


    # data = { :number_of_ids => int }
    class RequestIds < AbstractMessage
      def self.message_id
        8
      end

      def send
        [ self.class.message_id,
          1, # version
          @data[:number_of_ids]
        ]
      end
    end # RequestIds

    
    # data => { :contract => Contract }
    class RequestContractData < AbstractMessage
      def self.message_id
        9
      end

      def send(server)
        requireVersion(server, 4)

        queue = [
                 self.class.message_id,
                 2, # version
                 @data[:contract].symbol,
                 @data[:contract].sec_type,
                 @data[:contract].expiry,
                 @data[:contract].strike,
                 @data[:contract].right
                ]
        queue.push(@data[:contract].multiplier) if server[:version] >= 15

        queue.concat([
                      @data[:contract].exchange,
                      @data[:contract].currency,
                      @data[:contract].local_symbol,
                     ])

        queue
      end # send
    end # RequestContractData

    # data = { :ticker_id => int, :contract => Contract, :num_rows => int }
    class RequestMarketDepth < AbstractMessage
      def self.message_id
        10
      end

      def send(server)
        requireVersion(server, 6)

        queue = [ self.class.message_id,
                  3, # version
                  @data[:ticker_id]
                ]
        queue.concat(@data[:contract].serialize_short(server[:version]))
        queue.push(@data[:num_rows]) if server[:version] >= 19

        queue
                     
      end # send
    end # RequestMarketDepth

    # data = { :ticker_id => int }
    class CancelMarketDepth < AbstractMessage
      def self.message_id
        11
      end
      def send(server)
        requireVersion(self, 6)

        [ self.class.message_id,
          1, # version
          @data[:ticker_id]
        ]
      end
    end # CancelMarketDepth


    # data = { :all_messages => boolean }
    class RequestNewsBulletins < AbstractMessage
      def self.message_id
        12
      end

      def send(server)
        [ self.class.message_id,
          1, # version
          @data[:all_messages]
        ]
      end
    end # RequestNewsBulletins

    class CancelNewsBulletins < AbstractMessage
      def self.message_id
        13
      end

      def send(server)
        [ self.class.message_id,
          1 # version
        ]
      end
    end # CancelNewsBulletins

    # data = { :loglevel => int }
    class SetServerLoglevel < AbstractMessage
      def self.message_id
        14
      end

      def send(server)
        [ self.class.message_id,
          1, # version
          @data[:loglevel]
        ]
      end
    end # SetServerLoglevel

    # data = { :auto_bind => boolean }
    class RequestAutoOpenOrders < AbstractMessage
      def self.message_id
        15
      end

      def send(server)
        [ self.class.message_id,
          1, # version
          @data[:auto_bind]
        ]
      end
    end # RequestAutoOpenOrders


    class RequestAllOpenOrders < AbstractMessage
      def self.message_id
        16
      end

      def send(server)
        [ self.class.message_id,
          1 # version
        ]
      end
    end # RequestAllOpenOrders

    class RequestManagedAccounts < AbstractMessage
      def self.message_id
        17
      end

      def send(server)
        [ self.class.message_id,
          1 # version
        ]
      end
    end # RequestManagedAccounts

    # No idea what this is.
    # data = { :fa_data_type => int }
    class RequestFA < AbstractMessage
      def self.message_id
        18
      end

      def send(server)
        requireVersion(server, 13)

        [ self.class.message_id,
          1, # version
          @data[:fa_data_type]
        ]
      end
    end # RequestFA

    # No idea what this is.
    # data = { :fa_data_type => int, :xml => string }
    class ReplaceFA < AbstractMessage
      def self.message_id
        19
      end

      def send(server)
        requireVersion(server, 13)

        [ self.class.message_id,
          1, # version
          @data[:fa_data_type],
          @data[:xml]
        ]
      end
    end # ReplaceFA

    # data = { :ticker_id => int, 
    #          :contract => Contract,
    #          :end_date_time => string,
    #          :duration => string,
    #          :bar_size => int,
    #          :what_to_show => string,
    #          :use_RTH => int, # no idea what this is
    #          :format_date => int
    #        }
    class RequestHistoricalData < AbstractMessage
      def self.message_id
        20
      end

      def send(server)
        requireVersion(server, 16)

        queue = [ self.class.message_id,
                  3, # version
                  @data[:ticker_id]
                ]

        queue.concat(@data[:contract].serialize_long(server[:version]))

        queue.concat([
                      @data[:end_date_time],
                      @data[:bar_size]
                     ]) if server[:version] > 20


        queue.concat([
                      @data[:duration],
                      @data[:use_RTH],
                      @data[:what_to_show]
                     ])

        queue.push(@data[:format_date]) if server[:version] > 16

        if @data[:contract].sec_type.upcase == "BAG"
          queue.concat(@data[:contract].serialize_combo_legs)
        end

        queue
      end
    end # RequestHistoricalData

    # data = { :ticker_id => int,
    #          :contract => Contract,
    #          :exercise_action => int,
    #          :exercise_quantity => int,
    #          :account => string,
    #          :override => int } ## override? override what?
    class ExerciseOptions < AbstractMessage
      def self.message_id
        21
      end

      def send(server)

        requireVersion(server, 21)

        q = [self.class.message_id,
             1, # version
             @data[:ticker_id]
            ]
        q.concat(@data[:contract].serialize_long(server[:version]))
        q.concat([
                  @data[:exercise_action],
                  @data[:exercise_quantity],
                  @data[:account],
                  @data[:override]
                 ])
       
      end
    end # ExerciseOptions

    # data = { :ticker_id => int,
    #          :scanner_subscription => ScannerSubscription
    #        }
    class RequestScannerSubscription < AbstractMessage
      def self.message_id
        22
      end

      def send(server)
        requireVersion(server, 24)

        [
         self.class.message_id,
         3, # version
         @data[:ticker_id],
         @data[:subscription].number_of_rows,
         nilFilter(@data[:subscription].number_of_rows),
         @data[:subscription].instrument,
         @data[:subscription].location_code,
         @data[:subscription].scan_code,
         nilFilter(@data[:subscription].above_price),
         nilFilter(@data[:subscription].below_price),
         nilFilter(@data[:subscription].above_volume),
         nilFilter(@data[:subscription].market_cap_above),
         @data[:subscription].moody_rating_above,
         @data[:subscription].moody_rating_below,
         @data[:subscription].sp_rating_above,
         @data[:subscription].sp_rating_below,
         @data[:subscription].maturity_date_above,
         @data[:subscription].maturity_date_below,
         nilFilter(@data[:subscription].coupon_rate_above),
         nilFilter(@data[:subscription].coupon_rate_below),
         @data[:subscription].exclude_convertible,
         (server[:version] >= 25 ? [ @data[:subscription].average_option_volume_above,
                                     @data[:subscription].scanner_setting_pairs ] : []),
         
         (server[:version] >= 27 ? [ @data[:subscription].stock_type_filter ] : []),
        ].flatten
        
      end
    end # RequestScannerSubscription


    # data = { :ticker_id => int }
    class CancelScannerSubscription
      def self.message_id
        23
      end 

      def send(server)
        requireVersion(server, 24)
        [self.class.message_id,
         1, # version
         @data[:ticker_id]
        ]
      end
    end # CancelScannerSubscription


    class RequestScannerParameters
      def self.message_id
        24
      end

      def send(server)
        requireVersion(server, 24)

        [ self.class.message_id,
          1 # version
        ]
      end
    end # RequestScannerParameters


    # data = { :ticker_id => int }
    class CancelHistoricalData
      def self.message_id
        25
      end

      def send(server)
        requireVersion(server, 24)
        [ self.class.message_id,
          1, # version
          @data[:ticker_id]
        ]
      end
    end # CancelHistoricalData

end # module OutgoingMessages

  ################################################################
  #### end outgoing messages
  ################################################################



  ################################################################
  #### Incoming messages
  ################################################################

  module IncomingMessages
    Classes = Array.new

    #
    # This is just a basic generic message from the server.
    #
    # Class variables:
    # @@message_id - integer message id.
    #
    # Instance attributes:
    # :data - Hash of actual data read from a stream. 
    #
    # Override the load(socket) method in your subclass to do actual reading into @data.
    #
    class AbstractMessage
      attr_accessor :data

      def self.message_id
        raise Exception("AbstractMessage.message_id called - you need to override this in a subclass.")
      end


      def initialize(socket, server_version)
        raise Exception.new("Don't use AbstractMessage directly; use the subclass for your specific message type") if self.class.name == "AbstractMessage"
        IBLogger.debug(" * loading #{self.class.name}")

        @data = Hash.new
        @socket = socket
        @server_version = server_version

        self.load()

        @socket = nil
        

        IBLogger.debug(" * New #{self.class.name}: #{ self.inspect }")
      end

      def AbstractMessage.inherited(by)
        super(by)
        Classes.push(by)
      end

      def load
        raise Exception.new("Don't use AbstractMessage; override load() in a subclass.")
      end

      protected

      #
      # Load @data from the socket according to the given map.
      #
      # map is a series of Arrays in the format [ [ :name, :type ] ], e.g. autoload([:version, :int ], [:ticker_id, :int])
      # type identifiers must have a corresponding read_type method on socket (read_int, etc.).
      #
      def autoload(*map)
        #IBLogger.debug("autoloading map: " + map.inspect)
        map.each { |spec|
          @data[spec[0]] = @socket.__send__(("read_" + spec[1].to_s).to_sym)
        }
      end

      # version_load loads map only if @data[:version] is >= required_version.
      def version_load(required_version, map)
        autoload(map) if @data[:version] >= required_version 
      end

    end # class AbstractMessage


    ### Actual message classes
    
    # The IB code seems to dispatch up to two wrapped objects for this message, a tickPrice
    # and sometimes a tickSize, which seems to be identical to the TICK_SIZE object.
    #
    # Important note from
    # http://chuckcaplan.com/twsapi/index.php/void%20tickPrice%28%29 :
    #
    # "The low you get is NOT the low for the day as you'd expect it
    # to be. It appears IB calculates the low based on all
    # transactions after 4pm the previous day. The most inaccurate
    # results occur when the stock moves up in the 4-6pm aftermarket
    # on the previous day and then gaps open upward in the
    # morning. The low you receive from TWS can be easily be several
    # points different from the actual 9:30am-4pm low for the day in
    # cases like this. If you require a correct traded low for the
    # day, you can't get it from the TWS API. One possible source to
    # help build the right data would be to compare against what Yahoo
    # lists on finance.yahoo.com/q?s=ticker under the "Day's Range"
    # statistics (be careful here, because Yahoo will use anti-Denial
    # of Service techniques to hang your connection if you try to
    # request too many bytes in a short period of time from them). For
    # most purposes, a good enough approach would start by replacing
    # the TWS low for the day with Yahoo's day low when you first
    # start watching a stock ticker; let's call this time T. Then,
    # update your internal low if the bid or ask tick you receive is
    # lower than that for the remainder of the day. You should check
    # against Yahoo again at time T+20min to handle the occasional
    # case where the stock set a new low for the day in between
    # T-20min (the real time your original quote was from, taking into
    # account the delay) and time T. After that you should have a
    # correct enough low for the rest of the day as long as you keep
    # updating based on the bid/ask. It could still get slightly off
    # in a case where a short transaction setting a new low appears in
    # between ticks of data that TWS sends you.  The high is probably
    # distorted in the same way the low is, which would throw your
    # results off if the stock traded after-hours and gapped down. It
    # should be corrected in a similar way as described above if this
    # is important to you."
    #
    
    class TickPrice < AbstractMessage
      def self.message_id
        1
      end

      def load
        autoload([:version, :int], [:ticker_id, :int], [:tick_type, :int], [:price, :decimal])
        
        version_load(2, [:size, :int])
        version_load(3, [:can_auto_execute, :int])
        
        if @data[:version] >= 2
          # the IB code translates these into 0, 3, and 5, respectively, and wraps them in a TICK_SIZE-type wrapper.
          @data[:type] = case @data[:tick_type]
                         when 1
                           :bid
                         when 2
                           :ask
                         when 4
                           :last
                         when 6
                           :high
                         when 7
                           :low
                         when 9
                           :close
                         else
                           nil
                         end
        end

      end # load
      
      def inspect
        "Tick (" + @data[:type].to_s + " at "  + @data[:price].to_digits + ") " + super.inspect
      end
      
      def to_human
        @data[:size].to_s + " " + @data[:type].to_s + " at " + @data[:price].to_digits
      end

    end # TickPrice



    class TickSize < AbstractMessage
      def self.message_id
        2
      end

      def load
        autoload([:version, :int], [:ticker_id, :int], [:tick_type, :int], [:size, :int])
        @data[:type] = case @data[:tick_type]
                       when 0
                         :bid
                       when 3
                         :ask
                       when 5
                         :last
                       when 8
                         :volume
                       else
                         nil
                       end
      end
      
      def to_human
        @data[:type].to_s + " size: " +  @data[:size].to_s
      end
    end # TickSize



    class OrderStatus < AbstractMessage
      def self.message_id
        3
      end

      def load
        autoload([:version, :int], [:id, :int], [:status, :string], [:filled, :int], [:remaining, :int],
                 [:average_fill_price, :decimal])

        version_load(2, [:perm_id, :int])
        version_load(3, [:parent_id, :int])
        version_load(4, [:last_fill_price, :decimal])
        version_load(5, [:client_id, :int])
      end
    end


    class Error < AbstractMessage
      def self.message_id
        4
      end
      
      def load
        @data[:version] = @socket.read_int

        if @data[:version] < 2
          @data[:message] = @socket.read_string
        else
          autoload([:id, :int], [:code, :int], [:message, :string])
        end
      end

    end # class ErrorMessage

    class OpenOrder < AbstractMessage
      attr_accessor :order, :contract

      def self.message_id
        5
      end

      def load
        @order = Datatypes::Order.new
        @contract = Datatypes::Contract.new

        autoload([:version, :int])

        @order.id = @socket.read_int

        @contract.symbol = @socket.read_string
        @contract.sec_type = @socket.read_string
        @contract.expiry = @socket.read_string
        @contract.strike = @socket.read_decimal
        @contract.right = @socket.read_string
        @contract.exchange = @socket.read_string
        @contract.currency = @socket.read_string

        @contract.local_symbol = @socket.read_string if @data[:version] >= 2

        @order.action = @socket.read_string
        @order.total_quantity = @socket.read_int
        @order.order_type = @socket.read_string
        @order.limit_price = @socket.read_decimal
        @order.aux_price = @socket.read_decimal
        @order.tif = @socket.read_string
        @order.oca_group = @socket.read_string
        @order.account = @socket.read_string
        @order.open_close = @socket.read_string
        @order.origin = @socket.read_int
        @order.order_ref = @socket.read_string

        @order.client_id = @socket.read_int if @data[:version] >= 3

        if @data[:version] >= 4
          @order.perm_id = @socket.read_int
          @order.ignore_rth = (@socket.read_int == 1)
          @order.hidden = (@socket.read_int == 1)
          @order.discretionary_amount = @socket.read_decimal
        end

        @order.good_after_time = @socket.read_string if @data[:version] >= 5
        @order.shares_allocation = @socket.read_string if @data[:version] >= 6

        if @data[:version] >= 7
          @order.fa_group = @socket.read_string
          @order.fa_method = @socket.read_string
          @order.fa_percentage = @socket.read_string
          @order.fa_profile = @socket.read_string
        end

        @order.good_till_date = @socket.read_string if @data[:version] >= 8

        if @data[:version] >= 9
          @order.rule_80A = @socket.read_string
          @order.percent_offset = @socket.read_decimal
          @order.settling_firm = @socket.read_string
          @order.short_sale_slot = @socket.read_int
          @order.designated_location = @socket.read_string
          @order.auction_strategy = @socket.read_int
          @order.starting_price = @socket.read_decimal
          @order.stock_ref_price = @socket.read_decimal
          @order.delta = @socket.read_decimal
          @order.stock_range_lower = @socket.read_decimal
          @order.stock_range_upper = @socket.read_decimal
          @order.display_size = @socket.read_int
          @order.rth_only = @socket.read_boolean
          @order.block_order = @socket.read_boolean
          @order.sweep_to_fill = @socket.read_boolean
          @order.all_or_none = @socket.read_boolean
          @order.min_quantity = @socket.read_int
          @order.oca_type = @socket.read_int
          @order.eTrade_only = @socket.read_boolean
          @order.firm_quote_only = @socket.read_boolean
          @order.nbbo_price_cap = @socket.read_decimal
        end

        if @data[:version] >= 10
          @order.parent_id = @socket.read_int
          @order.trigger_method = @socket.read_int
        end

        if @data[:version] >= 11
          @order.volatility = @socket.read_decimal
          @order.volatility_type = @socket.read_int

          if @data[:version] == 11
            @order.delta_neutral_order_type = ( @socket.read_int == 0 ? "NONE" : "MKT" )
          else
            @order.delta_neutral_order_type = @socket.read_string
            @order.delta_neutral_aux_price = @socket.read_decimal
          end

          @order.continuous_update = @socket.read_int
          if @server_version == 26
            @order.stock_range_lower = @socket.read_decimal
            @order.stock_range_upper = @socket.read_decimal
          end

          @order.reference_price_type = @socket.read_int
        end # if version >= 11


      end # load
    end # OpenOrder

    class AccountValue < AbstractMessage
      def self.message_id
        6
      end

      def load
        autoload([:version, :int], [:key, :string], [:val, :string], [:cur, :string])
        version_load(2, [:account_name, :string])
      end 
    end # AccountValue

    class PortfolioValue < AbstractMessage
      attr_accessor :contract

      def self.message_id
        7
      end

      def load
        @contract = Datatypes::Contract.new

        autoload([:version, :int])
        @contract.symbol = @socket.read_string
        @contract.sec_type = @socket.read_string
        @contract.expiry = @socket.read_string
        @contract.strike = @socket.read_decimal
        @contract.right = @socket.read_string
        @contract.currency = @socket.read_string
        @contract.local_symbol = @socket.read_string if @data[:version] >= 2

        autoload([:position, :int], [:market_price, :decimal], [:market_value, :decimal])
        version_load(3, [:average_cost, :decimal], [:unrealized_pnl, :decimal], [:realized_pnl, :decimal])
        version_load(4, [:account_name, :string])
      end
    end # PortfolioValue

    class AccountUpdateTime < AbstractMessage
      def self.message_id
        8
      end

      def load
        autoload([:version, :int], [:time_stamp, :string])
      end
    end # AccountUpdateTime


    class NextValidID < AbstractMessage
      def self.message_id
        9
      end
      
      def load
        autoload([:version, :int], [:order_id, :int])
      end
      
    end # NextValidIDMessage

    
    class ContractData < AbstractMessage
      attr_accessor :contract_details

      def self.message_id
        10
      end
      
      def load
        @contract_details = Datatypes::ContractDetails.new

        autoload([:version, :int])

        @contract_details.summary.symbol = @socket.read_string
        @contract_details.summary.sec_type = @socket.read_string
        @contract_details.summary.expiry = @socket.read_string
        @contract_details.summary.strike = @socket.read_decimal
        @contract_details.summary.right = @socket.read_string
        @contract_details.summary.exchange = @socket.read_string
        @contract_details.summary.currency = @socket.read_string
        @contract_details.summary.local_symbol = @socket.read_string

        @contract_details.market_name = @socket.read_string
        @contract_details.trading_class = @socket.read_string
        @contract_details.con_id = @socket.read_int
        @contract_details.min_tick = @socket.read_decimal
        @contract_details.multiplier = @socket.read_string
        @contract_details.order_types = @socket.read_string
        @contract_details.valid_exchanges = @socket.read_string
        @contract_details.price_magnifier = @socket.read_int if @data[:version] >= 2
        
      end
    end # ContractData


    class ExecutionData < AbstractMessage
      attr_accessor :contract, :execution

      def self.message_id
        11
      end

      def load
        @contract = Datatypes::Contract.new
        @execution = Datatypes::Execution.new

        autoload([:version, :int], [:order_id, :int])

        @contract.symbol = @socket.read_string
        @contract.sec_type = @socket.read_string
        @contract.expiry = @socket.read_string
        @contract.strike = @socket.read_decimal
        @contract.right = @socket.read_string
        @contract.currency = @socket.read_string
        @contract.local_symbol = @socket.read_string if @data[:version] >= 2

        @execution.order_id = @data[:order_id]
        @execution.exec_id = @socket.read_string
        @execution.time = @socket.read_string
        @execution.account_number = @socket.read_string
        @execution.exchange = @socket.read_string
        @execution.side = @socket.read_string
        @execution.shares = @socket.read_int
        @execution.price = @socket.read_decimal

        @execution.perm_id = @socket.read_int if @data[:version] >= 2
        @execution.client_id = @socket.read_int if @data[:version] >= 3
        @execution.liquidation = @socket.read_int if @data[:version] >= 4
      end
    end # ExecutionData

    class MarketDepth < AbstractMessage
      def self.message_id
        12
      end

      def load
        autoload([:version, :int], [:id, :int], [:position, :int], [:operation, :int], [:side, :int], [:price, :decimal], [:size, :int])
      end
    end # MarketDepth

    class MarketDepthL2 < AbstractMessage
      def self.message_id
        13
      end

      def load
        autoload([:version, :int], [:id, :int], [:position, :int], [:market_maker, :string], [:operation, :int], [:side, :int],
                 [:price, :decimal], [:size, :int])
      end
    end # MarketDepthL2


    class NewsBulletins < AbstractMessage
      def self.message_id
        14
      end

      def load
        autoload([:version, :int], [:news_message_id, :int], [:news_message_type, :int], [:news_message, :string], [:originating_exchange, :string])
      end
    end # NewsBulletins

    class ManagedAccounts < AbstractMessage
      def self.message_id
        15
      end

      def load
        autoload([:version, :int], [:accounts_list, :string])
      end
    end # ManagedAccounts

    # "Fa"?
    class ReceiveFa < AbstractMessage
      def self.message_id
        16
      end

      def load
        autoload([:version, :int], [:fa_data_type, :int], [:xml, :string])
      end
    end # ReceiveFa

    class HistoricalData < AbstractMessage
      def self.message_id
        17
      end

      def load
        autoload([:version, :int], [:req_id, :int])
        version_load(2, [:start_date_str, :string], [:end_date_str, :string])
        @data[:completed_indicator] = "finished-" + @data[:start_date_str] + "-" + @data[:end_date_str] if @data[:version] >= 2

        autoload([:item_count, :int])
        @data[:history] = Array.new(@data[:item_count]) {|index|
          {
            :date => @socket.read_string,
            :open => @socket.read_decimal,
            :high => @socket.read_decimal,
            :low => @socket.read_decimal,
            :close => @socket.read_decimal,
            :volume => @socket.read_int,
            :wap => @socket.read_decimal,
            :has_gaps => @socket.read_string
          }
        }

      end
    end # HistoricalData

    class BondContractData < AbstractMessage
      attr_accessor :contract_details
      def self.message_id
        18
      end

      def load
        @contract_details = Datatypes::ContractDetails.new
        @contract_details.summary.symbol = @socket.read_string
        @contract_details.summary.sec_type = @socket.read_string
        @contract_details.summary.cusip = @socket.read_string
        @contract_details.summary.coupon = @socket.read_decimal
        @contract_details.summary.maturity = @socket.read_string
        @contract_details.summary.issue_date = @socket.read_string
        @contract_details.summary.ratings = @socket.read_string
        @contract_details.summary.bond_type = @socket.read_string
        @contract_details.summary.coupon_type = @socket.read_string
        @contract_details.summary.convertible = @socket.read_boolean
        @contract_details.summary.callable = @socket.read_boolean
        @contract_details.summary.puttable = @socket.read_boolean
        @contract_details.summary.desc_append = @socket.read_string
        @contract_details.summary.exchange = @socket.read_string
        @contract_details.summary.currency = @socket.read_string
        @contract_details.market_name = @socket.read_string
        @contract_details.trading_class = @socket.read_string
        @contract_details.con_id = @socket.read_int
        @contract_details.min_tick = @socket.read_decimal
        @contract_details.order_types = @socket.read_string
        @contract_details.valid_exchanges = @socket.read_string
        
      end
    end # BondContractData

    class ScannerParameters < AbstractMessage
      def self.message_id
        19
      end

      def load
        autoload([:version, :int], [:xml, :string])
      end
    end # ScannerParamters


    class ScannerData < AbstractMessage
      attr_accessor :contract_details
      def self.message_id
        20
      end

      def load
        autoload([:version, :int], [:ticker_id, :int], [:number_of_elements, :int])
        @data[:results] = Array.new(@data[:number_of_elements]) { |index|
          {
            :rank => @socket.read_int
            ## TODO: Pick up here.
          }
        }

      end
    end # ScannerData

    ###########################################
    ###########################################
    ## End message classes
    ###########################################
    ###########################################

    Table = Hash.new
    Classes.each { |msg_class|
      Table[msg_class.message_id] = msg_class
    }

    IBLogger.debug("Incoming message class table is #{Table.inspect}")

  end # module IncomingMessages
  ################################################################
  #### End incoming messages
  ################################################################



end  # module IB

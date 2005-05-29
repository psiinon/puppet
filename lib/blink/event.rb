#!/usr/local/bin/ruby -w

# $Id$

# included so we can test object types
require 'blink'
require 'blink/type'

module Blink
    # events are transient packets of information; they result in one or more (or none)
    # subscriptions getting triggered, and then they get cleared
    # eventually, these will be passed on to some central event system
	class Event
        # subscriptions are permanent associations determining how different
        # objects react to an event
        class Subscription
            attr_accessor :source, :event, :target, :method

            def initialize(hash)
                @triggered = false

                hash.each { |method,value|
                    # assign each value appropriately
                    # this is probably wicked-slow
                    self.send(method.to_s + "=",value)
                }
                Blink.warning "New Subscription: '%s' => '%s'" %
                    [@source,@event]
            end

            # the transaction is passed in so that we can notify it if
            # something fails
            def trigger(transaction)
                # we need some mechanism for only triggering a subscription
                # once per transaction, but, um, we don't want it to only
                # be once per process lifetime
                # so, for now, just trigger as many times as we can, rather than
                # as few...
                unless @triggered
                    Blink.verbose "'%s' generated '%s'; triggering '%s' on '%s'" %
                        [@source,@event,@method,@target]
                    begin
                        if @target.respond_to?(@method)
                            @target.send(@method)
                        else
                            Blink.verbose "'%s' of type '%s' does not respond to '%s'" %
                                [@target,@target.class,@method.inspect]
                        end
                    rescue => detail
                        # um, what the heck do i do when an object fails to refresh?
                        # shouldn't that result in the transaction rolling back?
                        # XXX yeah, it should
                        Blink.error "'%s' failed to refresh: '%s'" %
                            [@target,detail]
                        raise
                        #raise "We need to roll '%s' transaction back" %
                            #transaction
                    end
                    #@triggered = true
                end
            end
        end

		attr_accessor :event, :object, :transaction

        @@events = []

        @@subscriptions = []

        def Event.process
            Blink.warning "Processing events"
            @@events.each { |event|
                @@subscriptions.find_all { |sub|
                    #Blink.warning "Sub source: '%s'; event object: '%s'" %
                    #    [sub.source.inspect,event.object.inspect]
                    sub.source == event.object and
                        (sub.event == event.event or
                         sub.event == :ALL_EVENTS)
                }.each { |sub|
                    Blink.notice "Found sub"
                    sub.trigger(event.transaction)
                }
            }

            @@events.clear
        end

        def Event.subscribe(hash)
            if hash[:event] == '*'
                hash[:event] = :ALL_EVENTS
            end
            sub = Subscription.new(hash)

            # add to the correct area
            @@subscriptions.push sub
        end

		def initialize(args)
            unless args.include?(:event) and args.include?(:object)
				raise "Event.new called incorrectly"
			end

			@event = args[:event]
			@object = args[:object]
			@transaction = args[:transaction]

            Blink.warning "New Event: '%s' => '%s'" %
                [@object,@event]

            # initially, just stuff all instances into a central bucket
            # to be handled as a batch
            @@events.push self
		end
	end
end


#---------------------------------------------------------------
# here i'm separating out the methods dealing with handling events
# currently not in use, so...

class Blink::NotUsed
    #---------------------------------------------------------------
    # return action array
    # these are actions to use for responding to events
    # no, this probably isn't the best way, because we're providing
    # access to the actual hash, which is silly
    def action
        if not defined? @actions
            puts "defining action hash"
            @actions = Hash.new
        end
        @actions
    end
    #---------------------------------------------------------------

    #---------------------------------------------------------------
    # call an event
    # this is called on subscribers by the trigger method from the obj
    # which sent the event
    # event handling should probably be taking place in a central process,
    # but....
    def event(event,obj)
        Blink.debug "#{self} got event #{event} from #{obj}"
        if @actions.key?(event)
            Blink.debug "calling it"
            @actions[event].call(self,obj,event)
        else
            p @actions
        end
    end
    #---------------------------------------------------------------

    #---------------------------------------------------------------
    # subscribe to an event or all events
    # this entire event system is a hack job and needs to
    # be replaced with a central event handler
    def subscribe(args,&block)
        obj = args[:object]
        event = args[:event] || '*'.intern
        if obj.nil? or event.nil?
            raise "subscribe was called wrongly; #{obj} #{event}"
        end
        obj.action[event] = block
        #events.each { |event|
            unless @notify.key?(event)
                @notify[event] = Array.new
            end
            unless @notify[event].include?(obj)
                Blink.debug "pushing event '%s' for object '%s'" % [event,obj]
                @notify[event].push(obj)
            end
        #	}
        #else
        #	@notify['*'.intern].push(obj)
    end
    #---------------------------------------------------------------

    #---------------------------------------------------------------
    # initiate a response to an event
    def trigger(event)
        subscribers = Array.new
        if @notify.include?('*') and @notify['*'].length > 0
            @notify['*'].each { |obj| subscribers.push(obj) }
        end
        if (@notify.include?(event) and (! @notify[event].empty?) )
            @notify[event].each { |obj| subscribers.push(obj) }
        end
        Blink.debug "triggering #{event}"
        subscribers.each { |obj|
            Blink.debug "calling #{event} on #{obj}"
            obj.event(event,self)
        }
    end
    #---------------------------------------------------------------

    #---------------------------------------------------------------
end # Blink::Type

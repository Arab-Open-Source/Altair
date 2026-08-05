# Altair — controller-level exception handling.
#
# `Altair::Controller::RescueFrom` backs the `rescue_from` controller DSL.
# A controller names an exception class and a handler method; when an
# action (or one of its callbacks) raises a matching exception, the router's
# dispatch wrapper invokes the handler instead of letting the error bubble
# to the application's error pages. Handlers inherit across the controller
# hierarchy, and subclass exceptions match the registered type.
#
# Matching is captured as a compiled proc per registration (`e.is_a?(Foo)`),
# not a runtime class lookup — Crystal exposes no reflection for dynamic
# `is_a?` calls, so the type check happens at compile time.
module Altair::Controller::RescueFrom
  # A single rescue: the exception it answers for, the handler method, the
  # actions it applies to, and the compiled match-and-invoke procs.
  record RescueHandler,
    exception_name : String,
    method_name : String,
    only : Array(String) = [] of String,
    except : Array(String) = [] of String,
    match : Proc(Exception, Bool) = ->(e : Exception) { false },
    run : Proc(Altair::Controller, Exception, Nil) = ->(controller : Altair::Controller, e : Exception) { } do
    # True when the handler applies to `action`: listed in `only:` when
    # given, and not listed in `except:`.
    def applies_to?(action : String) : Bool
      return false if !only.empty? && !only.includes?(action)
      return false if except.includes?(action)
      true
    end
  end

  # Handlers keyed by the declaring controller's class name, so inherited
  # rescues resolve through the same chain registry the callbacks use.
  @@handlers = {} of String => Array(RescueHandler)

  def self.add_handler(class_name : String, handler : RescueHandler) : Nil
    (@@handlers[class_name] ||= [] of RescueHandler) << handler
  end

  # The handlers declared by `class_name`, in declaration order.
  def self.handlers_of(class_name : String) : Array(RescueHandler)
    @@handlers[class_name]? || [] of RescueHandler
  end
end

# Altair — controller callbacks.
#
# `Altair::Controller::Callbacks` backs the `before_action` /
# `after_action` / `skip_before_action` / `skip_after_action` controller
# DSL. Each callback pairs a filter method with the actions it applies to
# (`only:` / `except:`), plus a proc captured at declaration time so the
# compiler checks the filter method exists. The router's dispatch wrapper
# runs before callbacks, then the action, then after callbacks; a before
# callback that writes a response (render, redirect, head) halts the chain
# — the action and its after callbacks are skipped.
#
# Registrations are keyed by controller class name (not the class object —
# Crystal's exact-key `Hash` check rejects subclass metaclasses), which
# lets inherited callbacks accumulate across the superclass chain while a
# subclass's `skip_before_action` removes an ancestor's filter for selected
# actions.
module Altair::Controller::Callbacks
  # A single callback: the filter's name, the actions it applies to and
  # the ones it skips, and the invocation — emitted as a typed proc so a
  # typo in the filter name is a compile error.
  record Callback,
    method_name : String,
    only : Array(String) = [] of String,
    except : Array(String) = [] of String,
    run : Proc(Altair::Controller, Nil) = ->(controller : Altair::Controller) { } do
    # True when the callback applies to `action`: listed in `only:`
    # when given, and not listed in `except:`.
    def applies_to?(action : String) : Bool
      return false if !only.empty? && !only.includes?(action)
      return false if except.includes?(action)
      true
    end
  end

  # Each controller class records its own superclass chain here at
  # definition time (from `Altair::Controller::Callbacks::record_chain`).
  # Crystal exposes no runtime ancestry introspection, so the router walks
  # this registry instead of reflection.
  @@chains = {} of String => Array(String)
  @@before = {} of String => Array(Callback)
  @@after = {} of String => Array(Callback)
  @@skip_before = {} of String => Array(Callback)
  @@skip_after = {} of String => Array(Callback)

  # Records `class_name`'s superclass chain — itself first, then each
  # ancestor down to (but not including) `Altair::Controller`.
  def self.record_chain(class_name : String, ancestors : Array(String)) : Nil
    @@chains[class_name] = ancestors
  end

  # The recorded chain for `class_name` (self-first), or just the name
  # itself when the class was never seen.
  def self.chain_of(class_name : String) : Array(String)
    @@chains[class_name]? || [class_name]
  end

  def self.add_before(klass : Altair::Controller.class, callback : Callback) : Nil
    list_add(@@before, klass, callback)
  end

  def self.add_after(klass : Altair::Controller.class, callback : Callback) : Nil
    list_add(@@after, klass, callback)
  end

  def self.add_skip_before(klass : Altair::Controller.class, callback : Callback) : Nil
    list_add(@@skip_before, klass, callback)
  end

  def self.add_skip_after(klass : Altair::Controller.class, callback : Callback) : Nil
    list_add(@@skip_after, klass, callback)
  end

  # The callbacks registered by `klass_name`, in declaration order.
  def self.list(kind : Symbol, klass_name : String) : Array(Callback)
    (kind == :before ? @@before : @@after)[klass_name]? || [] of Callback
  end

  # The skip markers registered by `klass_name`.
  def self.skips(kind : Symbol, klass_name : String) : Array(Callback)
    (kind == :before ? @@skip_before : @@skip_after)[klass_name]? || [] of Callback
  end

  private def self.list_add(list : Hash(String, Array(Callback)), klass : Altair::Controller.class, callback : Callback) : Nil
    (list[klass.name] ||= [] of Callback) << callback
  end
end

# Altair — htmx integration.
#
# htmx is optional and opt-in: nothing here runs or loads unless an
# application uses it. The framework pins the newest htmx release as its
# default and serves it from a CDN; applications can override the version,
# the source or both through the config or per call. The request and
# response helpers make htmx-driven flows read naturally in controllers.
module Altair
  module Htmx
    # The htmx version served by default — the newest release when the
    # framework was built. Override it with `config.htmx_version`.
    VERSION = "2.0.10"

    # The CDN the default htmx version is served from.
    CDN = "https://unpkg.com/htmx.org@#{VERSION}/dist/htmx.min.js"

    # The header htmx sends on every htmx-driven request.
    REQUEST_HEADER = "HX-Request"

    # Response-header helpers for htmx, included into the controller base.
    # After an htmx request an action can steer the browser — swap regions,
    # redirect, refresh or push history — without writing any JavaScript:
    #
    # ```
    # def create : Nil
    #   # ... save ...
    #   hx_trigger(:post_created)
    #   render :index, layout: false
    # end
    # ```
    module Headers
      # Tells the client to trigger one or more events, e.g.
      # `hx_trigger(:post_created)` or `hx_trigger(:a, :b)`.
      def hx_trigger(*events : Symbol) : Nil
        response.headers["HX-Trigger"] = events.map(&.to_s).join(",")
      end

      # Triggers one or more events after the new content settles, e.g.
      # `hx_trigger_after_settle(:list_updated)`.
      def hx_trigger_after_settle(*events : Symbol) : Nil
        response.headers["HX-Trigger-After-Settle"] = events.map(&.to_s).join(",")
      end

      # Triggers one or more events after the new content swaps in, e.g.
      # `hx_trigger_after_swap(:list_updated)`.
      def hx_trigger_after_swap(*events : Symbol) : Nil
        response.headers["HX-Trigger-After-Swap"] = events.map(&.to_s).join(",")
      end

      # Targets a different element than the `hx-target` default, e.g.
      # `hx_retarget("#sidebar")`.
      def hx_retarget(selector : String) : Nil
        response.headers["HX-Retarget"] = selector
      end

      # Re-selects the swapped content with a different CSS selector, e.g.
      # `hx_reselect("#task-list li")`.
      def hx_reselect(selector : String) : Nil
        response.headers["HX-Reselect"] = selector
      end

      # Tells an `hx-trigger="every 5s"` poll to stop.
      def hx_stop_polling : Nil
        response.headers["HX-Stop-Polling"] = "true"
      end

      # Redirects the browser to `path` when the response completes.
      def hx_redirect(path : String) : Nil
        response.headers["HX-Redirect"] = path
      end

      # Navigates the browser to `path` without a full page load.
      def hx_location(path : String) : Nil
        response.headers["HX-Location"] = path
      end

      # Refreshes the page when the response completes.
      def hx_refresh : Nil
        response.headers["HX-Refresh"] = "true"
      end

      # Pushes `path` into the browser history without navigating.
      def hx_push_url(path : String) : Nil
        response.headers["HX-Push-Url"] = path
      end
    end
  end
end

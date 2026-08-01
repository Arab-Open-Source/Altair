# Altair — the batteries-included web framework for Crystal.
#
# This is the framework's entry point. Requiring `altair` loads every
# component of the framework in dependency order: the exception hierarchy,
# the configuration system, the support utilities, the HTTP abstractions, the
# application core and finally the server. Applications never require
# individual files — they require this single entry point and the compiler
# resolves the rest.
module Altair
end

require "http/server"
require "uri"

require "./altair/core/version"
require "./altair/exceptions/error"
require "./altair/exceptions/configuration_error"
require "./altair/exceptions/http_error"
require "./altair/exceptions/method_not_allowed"
require "./altair/exceptions/payload_too_large"
require "./altair/support/inflector"
require "./altair/config/env"
require "./altair/config/environments/base"
require "./altair/config/config"
require "./altair/http/params"
require "./altair/http/request"
require "./altair/http/response"
require "./altair/view/htmx"
require "./altair/view/template"
require "./altair/view/helpers"
require "./altair/view/form_builder"
require "./altair/controller/base"
require "./altair/middleware/base"
require "./altair/middleware/logger"
require "./altair/middleware/static"
require "./altair/routing/segment"
require "./altair/routing/route"
require "./altair/routing/route_set"
require "./altair/routing/router"
require "./altair/core/error_pages"
require "./altair/core/request_handler"
require "./altair/core/application"
require "./altair/routing/dsl"
require "./altair/server/server"

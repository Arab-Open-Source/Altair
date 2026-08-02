# Blog — the shared controller base.
#
# It brings in the application's generated path helpers, so actions can
# call `posts_path`, `new_post_path`, `post_path(5)` and friends as plain
# methods.
abstract class ApplicationController < Altair::Controller
  include Blog::RouteHelpers
end

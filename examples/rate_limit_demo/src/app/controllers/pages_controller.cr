class PagesController < ApplicationController
  def index : Nil
    response.text("Welcome to RateLimitDemo — try /login, /api/data, /free")
  end

  def login : Nil
    response.text("login — 5/minute")
  end

  def api_data : Nil
    response.text("api data — 30/minute")
  end

  def free : Nil
    response.text("free — outside every rule, never limited")
  end
end

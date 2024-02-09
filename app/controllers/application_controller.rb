class ApplicationController < ActionController::Base
  def root
    raise StandardError, "This is a test exception" if params[:error]

    render plain: "Hello, World!"
  end
end

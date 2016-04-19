require "haml"
require "sinatra"

class CrowbarBootstrap < Sinatra::Base
  set :bind, "0.0.0.0"

  get '/' do
    haml :index
  end

  post "/bootstrap" do
    # set up database here
  end
end

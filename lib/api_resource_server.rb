require "api_resource_server/version"

require "active_support"
require "active_record"

# handles our scope definitions
require "autoscope"

module ApiResourceServer

  extend ActiveSupport::Autoload

  autoload :Model

end

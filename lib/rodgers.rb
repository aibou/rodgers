require 'slack-ruby-bot'
require 'aws-sdk'
require 'erb'
require 'resolv'
require 'ipaddr'

require 'rodgers/controller'
require 'rodgers/view'
require 'rodgers/model'
require 'rodgers/bot'

module Rodgers
  def self.start
    Bot.run
  end
end


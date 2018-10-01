module Rodgers
  class Bot < SlackRubyBot::Bot
    @controller = Rodgers::Controller.new(Rodgers::Model.new, Rodgers::View.new)
  end
end

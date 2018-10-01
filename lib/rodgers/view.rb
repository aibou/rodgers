module Rodgers
  class View < SlackRubyBot::MVC::View::Base
    def format_as_code_block(obj, options = {})
      say(
        channel: data.channel,
        text: <<~EOS
        ```
        #{recursive_to_string(obj, options).chomp}
        ```
        EOS
      )
    end

    def error(message, exception)
      say(
        channel: data.channel,
        text: "#{message}. `#{exception}`"
      )
    end

    private
    # hashやarrayを再帰でstringにしていく
    def recursive_to_string(obj, options = {})
      case obj
      when String
        unless options[:length].nil?
          sprintf("%+-#{options[:length]}s",obj)
        else
          obj
        end
      when Array
        str = obj.map do |e|
          recursive_to_string(e, options)
        end.join
        str << "\n" if obj.all?(String)
        str
      when Hash
        if options[:without_key]
          recursive_to_string(obj.values, options)
        else
          recursive_to_string(obj.map{|k,v|"#{k}: #{v}"}, options)
        end
      else
      end
    end
  end
end

require 'slack-ruby-bot'
require 'aws-sdk'
require 'erb'
require 'resolv'
require 'ipaddr'

class RodgersBot < SlackRubyBot::Bot
  help do
    title 'Rodgers BOT'
    desc  'https://en.wikipedia.org/wiki/Aaron_Rodgers'

    command 'ping' do
      desc 'Return "pong"'
    end

    command 'ip' do
      desc 'rodgers ip <account name> <search words>'
    end

    command 'tag' do
      desc 'rodgers tag '
    end
  end

  command 'ping' do |client, data, match|
    client.say(
      text: 'pong',
      channel: data.channel
    )
  end

  @credentials = Aws::CredentialProviderChain.new.resolve

  command 'ip' do |client, data, match|
    account, search_name, *_ = match["expression"].split(/\s+/)

    begin
      ssm_client = Aws::SSM::Client.new(region: 'ap-northeast-1', credentials: @credentials)
      account_id = ssm_client.get_parameter(name: "#{account}.account_id").parameter.value
    rescue Aws::SSM::Errors::ParameterNotFound
      client.say(
        text: "Not found '#{account}.account_id' in SSM ParameterStore. It could not be processed.",
        channel: data.channel
      )
      return
    end

    begin
      assume_role_credentials = Aws::AssumeRoleCredentials.new(
        client: Aws::STS::Client.new(region: 'ap-northeast-1', credentials: @credentials),
        role_arn: "arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
        role_session_name: 'rodgers'
      )

      aws_client = Aws::EC2::Client.new(region: 'ap-northeast-1', credentials: assume_role_credentials)
      hosts = []
      instances = aws_client.describe_instances(
        filters: [
          {
            name: "tag:opsworks:instance",
            values: ["*#{search_name}*"]
          }
        ]
      ).reservations.map(&:instances).flatten

      instances.each do |ec2|
        hosts << {
          private_ip: ec2.private_ip_address,
          hostname: Hash[*ec2.tags.map{|tag|[tag.key,tag.value]}.flatten]["opsworks:instance"],
        }
      end

      hosts.sort! do |v1, v2|
        v1[:hostname] <=> v2[:hostname]
      end

      client.say(
        text: <<~EOS,
        ```
        #{hosts.map{|e|"#{sprintf("%+-32s",e[:hostname])}\t#{e[:private_ip]}"}.join("\n")}
        ```
        EOS
        channel: data.channel
      )
    rescue Aws::STS::Errors::AccessDenied
      client.say(
        text: "Oops, denied assume_role to arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
        channel: data.channel
      )
    rescue Aws::EC2::Errors::UnauthorizedOperation
      client.say(
        text: "Oops, I might not have `ec2:DescribeInstances` permission. Please give me authority.",
        channel: data.channel
      )
    end
  end

  command 'tag' do |client, data, match|
    args = match["expression"].split(/\s+/)
    case args[0]
    # 対話

    when /show/
      _, arn, *_ = args
      service, region, account_id, resource_name = arn.split(/:/)[2..-1]
      assume_role_credentials = Aws::AssumeRoleCredentials.new(
        client: Aws::STS::Client.new(region: region, credentials: @credentials),
        role_arn: "arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
        role_session_name: 'rodgers'
      )
      aws_client = Aws::ResourceGroupsTaggingAPI::Client.new(region: region, credentials: assume_role_credentials)
      resources = aws_client.get_resources(resource_type_filters: [service]).
        resource_tag_mapping_list.
        select{|tag_mapping| tag_mapping.resource_arn.match(arn) }

      erb = <<~EOERB
        <% resources.each do |r| -%>
        <%= r.resource_arn %> has this tags:
        ```
        <% r.tags.each do |tag| -%>
        <%= sprintf("%+-20s",tag.key) %> <%= tag.value %>
        <% end -%>
        ```
             
        <% end -%>
        EOERB
      client.say(
        text: ERB.new(erb, nil, "-").result_with_hash(resources: resources),
        channel: data.channel
      )
      
    # 一発
    # rodgers tag arn:aws:... opsworks:stack hoge
    when /^arn:/
      arn, tag_name, tag_value, *_ = args
      if [arn, tag_name, tag_value].any?(&:nil?)
        client.say(
          text: "Too short args. ```",
          channel: data.channel
        )        
      end

      service, region, account_id, resource_name = arn.split(/:/)[2..-1]
      

      begin
        assume_role_credentials = Aws::AssumeRoleCredentials.new(
          client: Aws::STS::Client.new(region: region, credentials: @credentials),
          role_arn: "arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
          role_session_name: 'rodgers'
        )
        aws_client = Aws::ResourceGroupsTaggingAPI::Client.new(region: region, credentials: assume_role_credentials)
        resp = aws_client.tag_resources(resource_arn_list: [arn], tags: Hash[tag_name, tag_value])

        if resp.failed_resources_map.empty?
          client.say(
            text: "Tag attached to #{resource_name} on #{service}",
            channel: data.channel
          )
        else
          client.say(
            text: "Failed to attach tags to #{resource_name} on #{service}. #{resp.failed_resources_map}",
            channel: data.channel
          )
        end

      rescue Aws::STS::Errors::AccessDenied
        client.say(
          text: "Oops, access denied on assume_role. arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
          channel: data.channel
        )
      end
      # ID ref

    end
  end

  command 'rdsip' do |client, data, match|
    desc "Search ip from AWS\nrodgers ip <account name> <search word>"
    account, rds, *_ = match["expression"].split(/\s+/)

    begin
      ssm_client = Aws::SSM::Client.new(region: 'ap-northeast-1', credentials: @credentials)
      account_id = ssm_client.get_parameter(name: "#{account}.account_id").parameter.value
    rescue Aws::SSM::Errors::ParameterNotFound
      client.say(
        text: "Not found '#{account}.account_id' in SSM ParameterStore. It could not be processed.",
        channel: data.channel
      )
      return
    end

    begin
      assume_role_credentials = Aws::AssumeRoleCredentials.new(
        client: Aws::STS::Client.new(region: 'ap-northeast-1', credentials: @credentials),
        role_arn: "arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
        role_session_name: 'rodgers'
      )
      rds_client = Aws::RDS::Client.new(region: 'ap-northeast-1', credentials: assume_role_credentials)
      
      rds_client.describe_db_instances(
        filters: [
          {
            name: "db-instance-id",
            values: ["*#{rds_name}*"]
          }
        ]
      )

      ip = Resolv.getaddress("")
      if [IPAddr.new('10.0.0.0/8'), IPAddr.new('172.16.0.0/12'), IPAddr.new('192.168.0.0/16')].any?{|private_cidr| private_cidr.include? ip}
        client.say(
          text: "",
          channel: data.channel
        )
      end
      
    rescue Aws::STS::Errors::AccessDenied
      client.say(
        text: "Oops, denied assume_role to arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
        channel: data.channel
      )
    rescue Resolv::ResolvError
      client.say(
        text: "no address for #{}",
        channel: data.channel
      )
    end
  end
end

SlackRubyBot::Client.logger.level = Logger::INFO
RodgersBot.run

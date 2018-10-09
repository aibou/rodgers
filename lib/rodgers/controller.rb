# コマンド書く
# ActiveSupport::Callbacks でException周りをハンドルする

module Rodgers
  class Controller < SlackRubyBot::MVC::Controller::Base
    def ping
      view.say(channel: data.channel, text: "pong")
    end

    def ip
      account_name, search_name, *_ = match["expression"].split(/\s+/)
      account_id = fetch_account_id(account_name)
      credentials = assume_role_credentials(account_id)

      aws_client = Aws::EC2::Client.new(region: 'ap-northeast-1', credentials: credentials)
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
      view.format_as_code_block(hosts, length: 20, without_key: true)
    end

    def tag
      args = match["expression"].split(/\s+/)
      case args[0]

      when /^arn:/
        arn, tag_name, tag_value, *_ = args

        # 両方共nilの場合はそのARNについているtag一覧を表示
        # memo: 現状、resourcegroupstaggingapi に ARN指定するオプションがない
        # そのため、[serviceのtag APIを使う] か [rgta:GetResourcesをフィルタするか] の2択
        # 前者のほうが高速だが、clientとactionを変えるのが面倒、後者はpaginationのためワーストケースがかなり遅い
        if [tag_name, tag_value].all?(&:nil?)
          service, region, account_id, *resource_names = arn.split(/:/)[2..-1]
          aws_client = Aws::ResourceGroupsTaggingAPI::Client.new(region: region, credentials: credentials)
          page_token, tags = nil
          
          loop do
            resources = aws_client.get_resources(resource_type_filters: [service], starting_token: page_token)
            if resources.any? {|e| e.resource_arn == arn }
              tags = resources.find {|e| e.resource_arn == arn }
              break
            end
            break if resources.pagination_token.empty?
          end

          # 整形してview.say
        end
        
        # いずれかがnilの場合（というかtag_valueがnilの場合）はエラー
        if [tag_name, tag_value].any?(&:nil?)
          view.say(
            text: "Too short args.",
            channel: data.channel
          )
        end

        service, region, account_id, *resource_names = arn.split(/:/)[2..-1]
        resource_name = resource_names.join(':')

        credentials = assume_role_credentials(account_id)
        aws_client = Aws::ResourceGroupsTaggingAPI::Client.new(region: region, credentials: credentials)
        resp = aws_client.tag_resources(resource_arn_list: [arn], tags: Hash[tag_name, tag_value])

        if resp.failed_resources_map.empty?
          view.say(
            text: "Tag attached to #{resource_name} on #{service}",
            channel: data.channel
          )
        else
          view.say(
            text: "Failed to attach tags to #{resource_name} on #{service}. #{resp.failed_resources_map}",
            channel: data.channel
          )
        end
      end
    end

    def rdsip
      account_name, search_name, *_ = match["expression"].split(/\s+/)
      account_id = fetch_account_id(account_name)
      credentials = assume_role_credentials(account_id)

      begin
        rds_client = Aws::RDS::Client.new(region: 'ap-northeast-1', credentials: credentials)
        rdses = rds_client.describe_db_instances.db_instances.select{|rds|rds.db_instance_identifier =~ /#{search_name}/}

        hosts = rdses.map do |rds|
          ip = Resolv.getaddress(rds.endpoint.address)
          if [IPAddr.new('10.0.0.0/8'), IPAddr.new('172.16.0.0/12'), IPAddr.new('192.168.0.0/16')].any?{|private_cidr| private_cidr.include? ip}
            { private_ip: ip, db_instance_identifier: rds.db_instance_identifier }
          else
            ec2_client = Aws::EC2::Client.new(region: 'ap-northeast-1', credentials: credentials)
            private_ip = ec2_client.describe_network_interfaces(filters: [{name: 'association.public-ip', values: [ip]}]).network_interfaces[0].private_ip_address
            { private_ip: private_ip, db_instance_identifier: rds.db_instance_identifier }
          end
        end
      rescue Aws::RDS::Errors::AccessDenied => e
        view.error("Oops, got error", e)
      rescue Aws::EC2::Errors::AccessDenied => e
        view.error("Oops, got error", e)
      end

      view.format_as_code_block(hosts, length: 20, without_key: true)
    end

    private
    def assume_role_credentials(account_id)
      begin
        Aws::AssumeRoleCredentials.new(
          client: Aws::STS::Client.new(region: 'ap-northeast-1', credentials: Aws::CredentialProviderChain.new.resolve),
          role_arn: "arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}",
          role_session_name: 'rodgers'
        )
      rescue Aws::STS::Errors::AccessDenied
        view.error("Oops, denied assume_role to arn:aws:iam::#{account_id}:role/#{ENV["ASSUME_ROLE_NAME"]}", nil)
      end
    end

    def fetch_account_id(account_name)
      begin
        ssm_client = Aws::SSM::Client.new(region: 'ap-northeast-1', credentials: Aws::CredentialProviderChain.new.resolve)
        ssm_client.get_parameter(name: "#{account_name}.account_id").parameter.value
      rescue Aws::SSM::Errors::ParameterNotFound
        view.error("Not found '#{account}.account_id' in SSM ParameterStore. please store it to AWS in account id: #{Aws::STS::Client.new().get_caller_identity.account}", nil)
      end
    end
  end
end

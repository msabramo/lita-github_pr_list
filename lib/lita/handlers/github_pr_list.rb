require "lita"
require "json"

module Lita
  module Handlers
    class GithubPrList < Handler
      def initialize(robot)
        super
      end

      def self.default_config(config)
        config.github_organization = nil
        config.github_access_token = nil
        config.web_hook = nil
      end

      route(/pr list/i, :list_org_pr, command: true,
            help: { "pr list" => "List open pull requests for an organization." }
      )

      route(/pr add hooks/i, :add_pr_hooks, command: true,
            help: { "pr add hooks" => "Add a pr web hook to every repo in your organization." }
      )

      route(/pr remove hooks/i, :remove_pr_hooks, command: true,
            help: { "pr remove hooks" => "Remove the pr web hook from every repo in your organization." }
      )

      route(/pr alias user (\w*) (\w*)/i, :alias_user, command: true,
            help: { "pr alias user <GithubUsername> <HipchatUsername>" => "Create an alias to match a Github "\
                    "username to a Hipchat Username." }
      )

      http.post "/comment_hook", :comment_hook
      http.post "/check_list", :check_list
      http.post "/merge_request_action", :merge_request_action

      def list_org_pr(response)
        prs = Lita::GithubPrList::PullRequest.new({ github_organization: github_organization,
                                                    github_token: github_access_token,
                                                    response: response }).list
        mrs = redis.keys("gitlab_mr*").map { |key| redis.get(key) }
        requests = prs + mrs
        message = "I found #{requests.count} open pull requests for #{github_organization}\n"
        response.reply(message + requests.join("\n"))
      end

      def alias_user(response)
        Lita::GithubPrList::AliasUser.new({ response:response, redis: redis }).create_alias
      end

      def comment_hook(request, response)
        message = Lita::GithubPrList::CommentHook.new({ request: request, response: response, redis: redis }).message
        message_rooms(message, response)
      end

      def check_list(request, response)
        check_list_params = { request: request, response: response, redis: redis, github_token: github_access_token }
        Lita::GithubPrList::CheckList.new(check_list_params)
      end

      def message_rooms(message, response)
        rooms = Lita.config.adapter.rooms
        rooms ||= [:all]
        rooms.each do |room|
          target = Source.new(room: room)
          robot.send_message(target, message) unless message.nil?
        end

        response.body << "Nothing to see here..."
      end

      def add_pr_hooks(response)
        Lita::GithubPrList::WebHook.new(github_organization: github_organization, github_token: github_access_token,
                                        web_hook: web_hook, response: response, event_type: "pull_request").add_hooks
      end

      def remove_pr_hooks(response)
        Lita::GithubPrList::WebHook.new(github_organization: github_organization, github_token: github_access_token,
                                        web_hook: web_hook, response: response, event_type: "pull_request").remove_hooks
      end

      def merge_request_action(request, response)
        payload = JSON.parse(request.body.read)
        if payload["object_kind"] == "merge_request"
          Lita::GithubPrList::MergeRequest.new(payload["object_attributes"], redis: redis).handle
        end
      end

    private

      def github_organization
        Lita.config.handlers.github_pr_list.github_organization
      end

      def github_access_token
        Lita.config.handlers.github_pr_list.github_access_token
      end

      def web_hook
        Lita.config.handlers.github_pr_list.web_hook
      end
    end

    Lita.register_handler(GithubPrList)
  end
end

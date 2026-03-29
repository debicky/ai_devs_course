# frozen_string_literal: true

module Services
  module Reactor
    class Runner
      TASK_NAME    = 'reactor'
      MAX_ATTEMPTS = 5

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
        @parser     = StateParser.new
      end

      def call
        MAX_ATTEMPTS.times do |attempt_index|
          attempt = attempt_index + 1
          log("attempt #{attempt}/#{MAX_ATTEMPTS}: initializing board")

          initial_command = attempt == 1 ? 'start' : 'reset'
          initial_state   = issue_command(initial_command)
          log_state_summary(initial_state)

          plan = Navigator.new(initial_state: initial_state).plan
          log("planned #{plan.length} moves: #{plan.join(' ')}")

          final_state = execute_plan(plan)
          if final_state.terminal_flag?
            return {
              flag: final_state.flag,
              verification: { 'code' => final_state.code, 'message' => final_state.message },
              commands: [initial_command] + plan
            }
          end

          raise 'goal reached without flag in response' if final_state.reached_goal
          raise 'plan finished without reaching the goal' unless final_state.terminal_flag?
        rescue StandardError => e
          log("attempt #{attempt} failed: #{e.message}")
          raise if attempt == MAX_ATTEMPTS
        end

        raise 'Reactor task failed after maximum attempts'
      end

      private

      def execute_plan(plan)
        current_state = nil

        plan.each_with_index do |command, i|
          current_state = issue_command(command)
          log("step #{i + 1}/#{plan.length}: #{command} -> #{current_state.message}")
          return current_state if current_state.terminal_flag?
          raise 'robot was crushed during plan execution' if current_state.crushed?
        end

        current_state
      end

      def issue_command(command)
        response = @hub_client.verify_raw(task: TASK_NAME, answer: { command: command })
        state = @parser.parse(response)
        log("hub status=#{state.status_code} code=#{state.code} msg=#{state.message.inspect}")
        state
      end

      def log_state_summary(state)
        player = "player=(#{state.player_col},#{state.player_row})"
        goal   = "goal=(#{state.goal_col},#{state.goal_row})"
        blocks = state.blocks.map do |block|
          "c#{block.col}:#{block.top_row}-#{block.bottom_row}:#{block.direction}"
        end.join(' | ')
        log("#{player} #{goal} blocks=[#{blocks}]")
      end

      def log(message)
        @logger.puts("[reactor] #{message}")
      end
    end
  end
end

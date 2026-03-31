# frozen_string_literal: true

module Services
  module Reactor
    BoardState = Struct.new(
      :status_code,
      :code,
      :message,
      :board,
      :player_col,
      :player_row,
      :goal_col,
      :goal_row,
      :blocks,
      :reached_goal,
      :flag,
      keyword_init: true
    ) do
      def success?
        status_code == 200
      end

      def crushed?
        code == -920 || message.to_s.include?('crushed')
      end

      def terminal_flag?
        !flag.to_s.empty?
      end
    end

    class StateParser
      FLAG_REGEX = /\{FLG:[^}]+}/.freeze

      def parse(response)
        body = JSON.parse(response.body.to_s)
        BoardState.new(
          status_code: response.code.to_i,
          code: body['code'],
          message: body['message'],
          board: body['board'],
          player_col: body.dig('player', 'col'),
          player_row: body.dig('player', 'row'),
          goal_col: body.dig('goal', 'col'),
          goal_row: body.dig('goal', 'row'),
          blocks: parse_blocks(body['blocks']),
          reached_goal: body['reached_goal'] || body['message'].to_s.match?(FLAG_REGEX),
          flag: body['message'].to_s[FLAG_REGEX]
        )
      rescue JSON::ParserError => e
        raise "Invalid reactor API JSON: #{e.message}; body=#{response.body.inspect}"
      end

      private

      def parse_blocks(raw_blocks)
        Array(raw_blocks).map do |block|
          Block.new(
            col: block.fetch('col'),
            top_row: block.fetch('top_row'),
            bottom_row: block.fetch('bottom_row'),
            direction: block.fetch('direction')
          )
        end
      end
    end
  end
end


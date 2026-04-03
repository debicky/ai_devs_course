# frozen_string_literal: true

module Services
  module Foodwarehouse
    class Runner
      TASK_NAME = 'foodwarehouse'
      FOOD4CITIES_URL = 'https://hub.ag3nts.org/dane/food4cities.json'

      def initialize(hub_client:, http_client:, logger: $stdout)
        @hub  = hub_client
        @http = http_client
        @log  = logger
      end

      def call
        log '=== Starting foodwarehouse task ==='

        log 'Resetting state...'
        api(tool: 'reset')

        city_needs = fetch_city_needs
        log "Cities: #{city_needs.keys.join(', ')}"
        city_needs.each { |city, items| log "  #{city}: #{items.inspect}" }

        db_data = load_database

        create_all_orders(city_needs, db_data)

        log 'Verifying final state...'
        final = api(tool: 'orders', action: 'get')
        log "Final orders: #{final['count']}"
        Array(final['orders']).each do |o|
          log "  #{o['title']} -> dest=#{o['destination']} items=#{o['items']&.size} types"
        end

        log 'Calling done...'
        done = api(tool: 'done')
        flag = done['message'] || done.to_s
        log "Flag: #{flag}"

        { verification: done, flag: flag }
      end

      private

      def fetch_city_needs
        log 'Fetching food4cities.json...'
        response = @http.get(FOOD4CITIES_URL)
        JSON.parse(response.body)
      end

      def load_database
        log 'Querying database...'

        users = db_query('SELECT * FROM users WHERE is_active = 1')
        log "Users: #{users.size} active"

        destinations = db_query('SELECT * FROM destinations')
        dest_by_name = destinations.each_with_object({}) { |d, h| h[d['name'].downcase] = d['destination_id'] }
        log "Destinations: #{destinations.size} rows"

        { users: users, dest_by_name: dest_by_name }
      end

      def create_all_orders(city_needs, db_data)
        transport_users = db_data[:users].select { |u| u['role'] == 2 }
        log "Transport users: #{transport_users.map { |u| u['login'] }.join(', ')}"

        city_needs.each_with_index do |(city, items), idx|
          log "--- Order #{idx + 1}/#{city_needs.size}: #{city} ---"

          destination_code = resolve_destination(city, db_data[:dest_by_name])
          unless destination_code
            log "  ERROR: No destination for #{city}!"
            next
          end

          creator = transport_users[idx % transport_users.size]
          signature = generate_signature(login: creator['login'], birthday: creator['birthday'], destination: destination_code)
          log "  dest=#{destination_code} creator=#{creator['login']} sig=#{signature[0..11]}..."

          create_result = api(
            tool: 'orders', action: 'create',
            title: "Dostawa dla #{city.capitalize}",
            creatorID: creator['user_id'],
            destination: destination_code.to_s,
            signature: signature
          )

          order_id = create_result['id'] || create_result.dig('order', 'id')
          unless order_id
            log "  ERROR: Create failed — #{create_result['message']}"
            next
          end

          append_result = api(tool: 'orders', action: 'append', id: order_id, items: items)
          log "  Created #{order_id[0..11]}... #{append_result['message']}"
        end
      end

      def resolve_destination(city, dest_by_name)
        dest_by_name[city.downcase] || search_destination(city)
      end

      def search_destination(city)
        rows = db_query("SELECT destination_id FROM destinations WHERE LOWER(name) = '#{city.downcase}'")
        return nil unless rows.is_a?(Array) && !rows.empty?

        rows.first['destination_id']
      end

      def generate_signature(login:, birthday:, destination:)
        result = api(tool: 'signatureGenerator', action: 'generate', login: login, birthday: birthday, destination: destination)
        result['hash']
      end

      def api(**params)
        resp = @hub.verify_raw(task: TASK_NAME, answer: params)
        JSON.parse(resp.body)
      end

      def db_query(query)
        result = api(tool: 'database', query: query)
        result['reply'] || []
      end

      def log(msg)
        @log.puts("[foodwarehouse] #{msg}")
      end
    end
  end
end

# frozen_string_literal: true

module Services
  module Filesystem
    class Runner
      TASK_NAME = 'filesystem'

      # Cities and what they NEED (from ogłoszenia.txt)
      CITY_NEEDS = {
        'opalino'    => { 'chleb' => 45, 'woda' => 120, 'mlotek' => 6 },
        'domatowo'   => { 'makaron' => 60, 'woda' => 150, 'lopata' => 8 },
        'brudzewo'   => { 'ryz' => 55, 'woda' => 140, 'wiertarka' => 5 },
        'darzlubie'  => { 'wolowina' => 25, 'woda' => 130, 'kilof' => 7 },
        'celbowo'    => { 'kurczak' => 40, 'woda' => 125, 'mlotek' => 6 },
        'mechowo'    => { 'ziemniak' => 100, 'kapusta' => 70, 'marchew' => 65, 'woda' => 165, 'lopata' => 9 },
        'puck'       => { 'chleb' => 50, 'ryz' => 45, 'woda' => 175, 'wiertarka' => 7 },
        'karlinkowo' => { 'makaron' => 52, 'wolowina' => 22, 'ziemniak' => 95, 'woda' => 155, 'kilof' => 6 }
      }.freeze

      # People responsible for trade in each city (from rozmowy.txt)
      PEOPLE = {
        'natan_rams'    => { name: 'Natan Rams', city: 'domatowo' },
        'iga_kapecka'   => { name: 'Iga Kapecka', city: 'opalino' },
        'rafal_kisiel'  => { name: 'Rafal Kisiel', city: 'brudzewo' },
        'marta_frantz'  => { name: 'Marta Frantz', city: 'darzlubie' },
        'oskar_radtke'  => { name: 'Oskar Radtke', city: 'celbowo' },
        'eliza_redmann' => { name: 'Eliza Redmann', city: 'mechowo' },
        'damian_kroll'  => { name: 'Damian Kroll', city: 'puck' },
        'lena_konkel'   => { name: 'Lena Konkel', city: 'karlinkowo' }
      }.freeze

      # Goods for SALE and which cities sell them (from transakcje.txt)
      GOODS_FOR_SALE = {
        'ryz'       => %w[darzlubie opalino karlinkowo],
        'marchew'   => %w[puck],
        'chleb'     => %w[domatowo celbowo brudzewo],
        'wolowina'  => %w[opalino],
        'kilof'     => %w[puck mechowo celbowo],
        'wiertarka' => %w[karlinkowo domatowo],
        'maka'      => %w[brudzewo mechowo],
        'mlotek'    => %w[karlinkowo mechowo],
        'kapusta'   => %w[celbowo],
        'ziemniak'  => %w[domatowo darzlubie],
        'makaron'   => %w[opalino],
        'lopata'    => %w[brudzewo puck],
        'kurczak'   => %w[darzlubie]
      }.freeze

      def initialize(hub_client:, logger: $stdout)
        @hub = hub_client
        @log = logger
      end

      def call
        log 'Resetting filesystem...'
        api(action: 'reset')

        log 'Building batch operations...'
        ops = build_batch

        log "Sending #{ops.size} operations..."
        result = api_batch(ops)
        log "Batch result: #{result.inspect}"

        log 'Calling done...'
        done = api(action: 'done')
        flag = done['message'] || done.to_s
        log "Done: #{done.inspect}"
        log "Flag: #{flag}"

        { verification: done, flag: flag }
      end

      private

      def build_batch
        ops = []

        # Create directories
        ops << { action: 'createDirectory', path: '/miasta' }
        ops << { action: 'createDirectory', path: '/osoby' }
        ops << { action: 'createDirectory', path: '/towary' }

        # Create city files with JSON of needed goods
        CITY_NEEDS.each do |city, needs|
          ops << { action: 'createFile', path: "/miasta/#{city}", content: JSON.generate(needs) }
        end

        # Create person files with markdown link to their city
        PEOPLE.each do |filename, info|
          content = "#{info[:name]}\n\n[#{info[:city]}](/miasta/#{info[:city]})"
          ops << { action: 'createFile', path: "/osoby/#{filename}", content: content }
        end

        # Create goods files with markdown links to selling cities
        GOODS_FOR_SALE.each do |good, cities|
          links = cities.map { |c| "[#{c}](/miasta/#{c})" }.join("\n")
          ops << { action: 'createFile', path: "/towary/#{good}", content: links }
        end

        ops
      end

      def api(action:, **params)
        resp = @hub.verify_raw(task: TASK_NAME, answer: { action: action }.merge(params))
        JSON.parse(resp.body)
      end

      def api_batch(operations)
        resp = @hub.verify_raw(task: TASK_NAME, answer: operations)
        JSON.parse(resp.body)
      end

      def log(msg)
        @log.puts("[filesystem] #{msg}")
      end
    end
  end
end

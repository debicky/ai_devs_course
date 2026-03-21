# frozen_string_literal: true

module Services
  module FindHim
    class ToolExecutor
      TOOL_NAMES = %w[
        get_suspects
        get_power_plants
        get_person_locations
        get_closest_plant_for_suspect
        get_closest_plant
        calculate_distance
        get_access_level
        submit_answer
      ].freeze

      POWER_PLANT_CITY_COORDINATES = {
        'zabrze' => [50.3249, 18.7857],
        'piotrkw trybunalski' => [51.4052, 19.7030],
        'piotrkow trybunalski' => [51.4052, 19.7030],
        'grudziadz' => [53.4837, 18.7536],
        'tczew' => [54.0924, 18.7779],
        'radom' => [51.4027, 21.1471],
        'chelmno' => [53.3486, 18.4258],
        'zarnowiec' => [54.7941, 18.0044]
      }.freeze

      def initialize(hub_client:, suspects_loader:, distance_calculator:)
        @hub_client = hub_client
        @suspects_loader = suspects_loader
        @distance_calculator = distance_calculator
        @power_plants_cache = nil
        @person_locations_cache = {}
        @access_level_cache = {}
        @closest_plant_cache = {}
      end

      def call(name:, arguments:)
        raise ArgumentError, "Unknown tool: #{name}" unless TOOL_NAMES.include?(name)

        public_send(name, arguments)
      end

      def get_suspects(_arguments)
        { suspects: @suspects_loader.call }
      end

      def get_power_plants(_arguments)
        cached_power_plants
      end

      def get_person_locations(arguments)
        name = fetch_string(arguments, 'name')
        surname = fetch_string(arguments, 'surname')
        name, surname = resolve_suspect_name(name, surname)
        locations = cached_person_locations(name, surname)
        return { error: locations[:error] } if locations.is_a?(Hash) && locations.key?(:error)
        return { locations: [] } if locations.empty?

        { locations: locations }
      end

      def get_closest_plant_for_suspect(arguments)
        name = fetch_string(arguments, 'name')
        surname = fetch_string(arguments, 'surname')
        name, surname = resolve_suspect_name(name, surname)
        cache_key = suspect_cache_key(name, surname)
        return @closest_plant_cache[cache_key] if @closest_plant_cache.key?(cache_key)

        locations = cached_person_locations(name, surname)
        if locations.is_a?(Hash) && locations.key?(:error)
          result = { error: locations[:error] }
          @closest_plant_cache[cache_key] = result
          return result
        end

        if locations.empty?
          result = { error: 'No locations for this suspect.' }
          @closest_plant_cache[cache_key] = result
          return result
        end

        raw_plants = cached_power_plants
        plants = raw_plants[:powerPlants].select { |p| p.key?(:latitude) && p.key?(:longitude) }
        if plants.empty?
          result = { error: 'No power plants with coordinates available. Do not call get_closest_plant_for_suspect again — you cannot get closestPlantCode without coordinates. Report to the user that the API did not return plant coordinates, or try get_access_level and submit_answer only if you already have a closestPlantCode from a previous successful result.' }
          @closest_plant_cache[cache_key] = result
          return result
        end

        best_code = nil
        best_distance = Float::INFINITY
        locations.each do |loc|
          closest_plant, distance_km = plants.map do |p|
            d = @distance_calculator.call(
              lat1: loc[:latitude], lon1: loc[:longitude],
              lat2: p[:latitude], lon2: p[:longitude]
            )
            [p, d]
          end.min_by { |_, d| d }
          next unless distance_km < best_distance

          best_distance = distance_km
          best_code = closest_plant[:code]
        end

        result = { closestPlantCode: best_code, distanceKm: best_distance.round(3) }
        @closest_plant_cache[cache_key] = result
        result
      end

      def get_closest_plant(arguments)
        lat = Float(arguments.fetch('lat'))
        lon = Float(arguments.fetch('lon'))
        raw = cached_power_plants
        plants = raw[:powerPlants].select { |p| p.key?(:latitude) && p.key?(:longitude) }

        if plants.empty?
          return { error: 'No power plants with coordinates available; use get_power_plants then calculate_distance.' }
        end

        closest_plant, distance_km = plants.map do |p|
          d = @distance_calculator.call(lat1: lat, lon1: lon, lat2: p[:latitude], lon2: p[:longitude])
          [p, d]
        end.min_by { |_, d| d }

        { closestPlantCode: closest_plant[:code], distanceKm: distance_km.round(3) }
      end

      def calculate_distance(arguments)
        distance = @distance_calculator.call(
          lat1: arguments.fetch('lat1'),
          lon1: arguments.fetch('lon1'),
          lat2: arguments.fetch('lat2'),
          lon2: arguments.fetch('lon2')
        )

        { distanceKm: distance.round(3) }
      end

      def get_access_level(arguments)
        name = fetch_string(arguments, 'name')
        surname = fetch_string(arguments, 'surname')
        name, surname = resolve_suspect_name(name, surname)
        birth_year = Integer(arguments.fetch('birthYear'))
        key = "#{name}|#{surname}|#{birth_year}"
        return @access_level_cache[key] if @access_level_cache.key?(key)

        raw = @hub_client.fetch_access_level(name: name, surname: surname, birth_year: birth_year)
        if raw.is_a?(Hash) && raw.key?('error')
          return { error: raw['error'].to_s }
        end

        result = { accessLevel: extract_access_level(raw) }
        @access_level_cache[key] = result
        result
      end

      POWER_PLANT_FORMAT = /\APWR\d{4}[A-Z]{2}\z/

      def submit_answer(arguments)
        name = fetch_string(arguments, 'name')
        surname = fetch_string(arguments, 'surname')
        name, surname = resolve_suspect_name(name, surname)

        answer = {
          name: name,
          surname: surname,
          accessLevel: Integer(arguments.fetch('accessLevel')),
          powerPlant: fetch_string(arguments, 'powerPlant')
        }

        if answer[:accessLevel].zero?
          return {
            error: "accessLevel cannot be 0. The Hub API rejects it as 'Incorrect person identification'. If get_access_level returned 0, it means no valid access level was found. Do not submit an answer."
          }
        end
        if answer[:powerPlant].to_s.strip.downcase == 'unknown' || answer[:powerPlant].to_s.include?('power plants with coordinates')
          return {
            error: "powerPlant cannot be 'unknown' or an error message. Look at the get_closest_plant_for_suspect tool result for this suspect: it is JSON with key 'closestPlantCode' (e.g. PWR3847PL). Copy that exact value. If the result had 'error' instead of 'closestPlantCode', do not call submit_answer — the tool failed for this suspect."
          }
        end

        unless answer[:powerPlant].match?(POWER_PLANT_FORMAT)
          return {
            error: "powerPlant must be the exact closestPlantCode from get_closest_plant_for_suspect (format PWR + 4 digits + 2 letters, e.g. PWR3847PL). You passed: #{answer[:powerPlant].inspect}. Copy the 'closestPlantCode' value from the tool result."
          }
        end

        closest_result = cached_closest_plant_for(answer[:name], answer[:surname])
        if closest_result.nil?
          return {
            error: "Missing closest plant result for #{answer[:name]} #{answer[:surname]}. Call get_closest_plant_for_suspect for this suspect first, then copy its exact closestPlantCode into submit_answer."
          }
        end

        if closest_result[:error]
          return {
            error: "Cannot submit an answer for #{answer[:name]} #{answer[:surname]} because get_closest_plant_for_suspect returned an error: #{closest_result[:error]}"
          }
        end

        expected_code = closest_result[:closestPlantCode].to_s
        if expected_code.empty?
          return {
            error: "Missing closestPlantCode for #{answer[:name]} #{answer[:surname]}. Call get_closest_plant_for_suspect again only if you do not already have a valid result."
          }
        end

        unless answer[:powerPlant] == expected_code
          return {
            error: "powerPlant must exactly match the closestPlantCode previously returned for #{answer[:name]} #{answer[:surname]}. Expected #{expected_code.inspect}, got #{answer[:powerPlant].inspect}. Copy the exact value from the tool result; do not invent or reuse another plant code."
          }
        end

        valid_codes = cached_power_plants[:powerPlants].map { |p| p[:code].to_s }.uniq
        unless valid_codes.include?(answer[:powerPlant])
          return {
            error: "powerPlant must be one of the codes returned by get_closest_plant_for_suspect, not an invented value. You passed: #{answer[:powerPlant].inspect}. Valid codes from the API are: #{valid_codes.sort.join(', ')}. Use the closestPlantCode from the tool result for the chosen suspect."
          }
        end

        verification = @hub_client.verify(task: 'findhim', answer: answer)
        { submitted: true, answer: stringify_keys(answer), verification: verification }
      rescue Clients::HttpError => e
        if e.code == '400' && e.body.to_s.include?('Incorrect person identification')
          return {
            submitted: false,
            incorrect_person: { name: answer[:name], surname: answer[:surname] },
            answer: stringify_keys(answer),
            error: e.body
          }
        end
        raise
      end

      private

      def cached_power_plants
        return @power_plants_cache if @power_plants_cache

        @power_plants_cache = normalize_power_plants(@hub_client.fetch_find_him_locations)
      end

      def cached_person_locations(name, surname)
        key = "#{name}|#{surname}"
        return @person_locations_cache[key] if @person_locations_cache.key?(key)

        raw = @hub_client.fetch_person_locations(name: name, surname: surname)
        @person_locations_cache[key] = normalize_locations(raw)
      rescue Clients::HttpError => e
        err_msg = e.body.to_s.include?('not on the list') ? 'This person is not on the list of survivors. Use the exact name and surname from get_suspects (with Polish characters, e.g. Wacław not Waclaw).' : e.body.to_s
        @person_locations_cache[key] = { error: err_msg }
        { error: err_msg }
      end

      def normalize_power_plants(raw)
        plants = extract_array(raw)
        {
          powerPlants: plants.map { |plant| normalize_power_plant(plant) }
        }
      end

      def normalize_power_plant(plant)
        result = {
          code: fetch_string_from_hash(plant, %w[code powerPlant plantCode]),
          name: plant['name'] || plant['city']
        }
        lat, lon = coords_from_plant(plant)
        lat, lon = fallback_coords_for(result[:name]) if lat.nil? || lon.nil?
        result[:latitude]  = lat if lat
        result[:longitude] = lon if lon
        result.compact
      end

      def coords_from_plant(plant)
        keys_lat = %w[latitude lat]
        keys_lon = %w[longitude lon lng]
        return [fetch_float_from_hash(plant, keys_lat), fetch_float_from_hash(plant, keys_lon)] if hash_has_coord?(plant, keys_lat) && hash_has_coord?(plant, keys_lon)

        nested = plant['location'] || plant['coordinates'] || plant['coord'] || plant['position'] || plant['geo']
        return [nil, nil] unless nested.is_a?(Hash)

        lat = nested['latitude'] || nested['lat']
        lon = nested['longitude'] || nested['lon'] || nested['lng']
        return [nil, nil] if lat.to_s.strip.empty? || lon.to_s.strip.empty?

        [Float(lat), Float(lon)]
      rescue ArgumentError, TypeError
        [nil, nil]
      end

      def hash_has_coord?(hash, keys)
        keys.any? { |k| hash.key?(k) && hash[k].to_s.strip != '' }
      end

      NORMALIZE_PL = { 'ą' => 'a', 'ć' => 'c', 'ę' => 'e', 'ł' => 'l', 'ń' => 'n', 'ó' => 'o', 'ś' => 's', 'ź' => 'z', 'ż' => 'z' }.freeze

      def resolve_suspect_name(name, surname)
        suspects = @suspects_loader.call
        given_key = normalize_name_for_match("#{name}|#{surname}")
        match = suspects.find do |s|
          canonical = "#{s['name']}|#{s['surname']}"
          normalize_name_for_match(canonical) == given_key
        end
        match ? [match['name'], match['surname']] : [name, surname]
      end

      def normalize_name_for_match(str)
        s = str.to_s.downcase.strip
        NORMALIZE_PL.each { |k, v| s = s.gsub(k, v) }
        s
      end

      def fallback_coords_for(name)
        POWER_PLANT_CITY_COORDINATES[normalize_name_for_match(name)] || [nil, nil]
      end

      def normalize_locations(raw)
        extract_array(raw).map do |location|
          {
            latitude: fetch_float_from_hash(location, %w[latitude lat]),
            longitude: fetch_float_from_hash(location, %w[longitude lon lng])
          }
        end
      end

      def extract_access_level(raw)
        return Integer(raw['accessLevel']) if raw.is_a?(Hash) && raw.key?('accessLevel')
        return Integer(raw['access_level']) if raw.is_a?(Hash) && raw.key?('access_level')
        return Integer(raw['level']) if raw.is_a?(Hash) && raw.key?('level')

        raise ArgumentError, "Access level response missing numeric level: #{raw.inspect}"
      end

      def extract_array(raw)
        return raw if raw.is_a?(Array)
        return raw['locations'] if raw.is_a?(Hash) && raw['locations'].is_a?(Array)
        return raw['powerPlants'] if raw.is_a?(Hash) && raw['powerPlants'].is_a?(Array)
        return raw['plants'] if raw.is_a?(Hash) && raw['plants'].is_a?(Array)

        if raw.is_a?(Hash) && (plants = raw['power_plants'] || raw['powerPlants']) && plants.is_a?(Hash)
          return power_plants_hash_to_array(plants)
        end

        raise ArgumentError, "Expected array response, got: #{raw.inspect}"
      end

      def power_plants_hash_to_array(plants_hash)
        plants_hash.map do |city_name, attrs|
          (attrs.is_a?(Hash) ? attrs : {}).merge('name' => city_name.to_s)
        end
      end

      def fetch_string(arguments, key)
        value = arguments.fetch(key).to_s.strip
        return value unless value.empty?

        raise ArgumentError, "Tool argument #{key.inspect} must be a non-empty string"
      end

      def fetch_string_from_hash(hash, keys)
        key = keys.find { |candidate| hash.key?(candidate) && !hash[candidate].to_s.strip.empty? }
        raise ArgumentError, "Missing string key from #{keys.inspect} in #{hash.inspect}" if key.nil?

        hash.fetch(key).to_s.strip
      end

      def fetch_float_from_hash(hash, keys)
        key = keys.find { |candidate| hash.key?(candidate) }
        raise ArgumentError, "Missing coordinate key from #{keys.inspect} in #{hash.inspect}" if key.nil?

        Float(hash.fetch(key))
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid numeric value for #{key.inspect} in #{hash.inspect}"
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
      end

      def cached_closest_plant_for(name, surname)
        @closest_plant_cache[suspect_cache_key(name, surname)]
      end

      def suspect_cache_key(name, surname)
        "#{name}|#{surname}"
      end
    end
  end
end

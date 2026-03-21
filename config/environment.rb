# frozen_string_literal: true

require 'bundler/setup'

require 'dotenv/load' if Gem.loaded_specs.key?('dotenv')

require 'pry' if Gem.loaded_specs.key?('pry')

require 'csv'
require 'json'
require 'net/http'
require 'uri'

# Clients
require_relative '../app/clients/http_client'
require_relative '../app/clients/hub_client'
require_relative '../app/clients/llm_client'

# Services::People
require_relative '../app/services/people/csv_parser'
require_relative '../app/services/people/filter'
require_relative '../app/services/people/job_classifier'
require_relative '../app/services/people/transport_selector'
require_relative '../app/services/people/answer_builder'

# Services::FindHim
require_relative '../app/services/find_him/suspects_loader'
require_relative '../app/services/find_him/distance_calculator'
require_relative '../app/services/find_him/tool_executor'

# Tasks
require_relative '../app/tasks/people_task'
require_relative '../app/tasks/find_him_task'

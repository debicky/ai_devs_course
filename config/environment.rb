# frozen_string_literal: true

require 'bundler/setup'

require 'dotenv/load' if Gem.loaded_specs.key?('dotenv')

require 'pry' if Gem.loaded_specs.key?('pry')

require 'csv'
require 'date'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'

# Clients
require_relative '../app/clients/http_client'
require_relative '../app/clients/hub_client'
require_relative '../app/clients/llm_client'
require_relative '../app/clients/packages_client'

# S01 — Week 1 Services
require_relative '../app/s01/services/people/csv_parser'
require_relative '../app/s01/services/people/filter'
require_relative '../app/s01/services/people/job_classifier'
require_relative '../app/s01/services/people/transport_selector'
require_relative '../app/s01/services/people/answer_builder'

require_relative '../app/s01/services/find_him/suspects_loader'
require_relative '../app/s01/services/find_him/distance_calculator'
require_relative '../app/s01/services/find_him/tool_executor'

require_relative '../app/s01/services/proxy/session_store'
require_relative '../app/s01/services/proxy/tool_executor'
require_relative '../app/s01/services/proxy/conversation_runner'
require_relative '../app/s01/services/proxy/http_server'

require_relative '../app/s01/services/send_it/documentation_explorer'
require_relative '../app/s01/services/send_it/declaration_builder'

require_relative '../app/s01/services/railway/runner'

# S01 — Week 1 Tasks
require_relative '../app/s01/tasks/people_task'
require_relative '../app/s01/tasks/find_him_task'
require_relative '../app/s01/tasks/proxy_task'
require_relative '../app/s01/tasks/sendit_task'
require_relative '../app/s01/tasks/railway_task'

# S02 — Week 2 Services
require_relative '../app/s02/services/categorize/runner'

require_relative '../app/s02/services/electricity/pixel_solver'
require_relative '../app/s02/services/electricity/runner'

require_relative '../app/s02/services/failure/runner'

require_relative '../app/s02/services/mailbox/tool_executor'
require_relative '../app/s02/services/mailbox/runner'

require_relative '../app/s02/services/drone/runner'

# S02 — Week 2 Tasks
require_relative '../app/s02/tasks/categorize_task'
require_relative '../app/s02/tasks/electricity_task'
require_relative '../app/s02/tasks/mailbox_task'
require_relative '../app/s02/tasks/failure_task'
require_relative '../app/s02/tasks/drone_task'

# S03 — Week 3 Services
require_relative '../app/s03/services/evaluation/sensor_validator'
require_relative '../app/s03/services/evaluation/note_classifier'
require_relative '../app/s03/services/evaluation/runner'

# S03 — Week 3 Tasks
require_relative '../app/s03/tasks/evaluation_task'

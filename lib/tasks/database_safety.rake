# frozen_string_literal: true

# Defense-in-depth against destroying the local development database.
#
# A prior autonomous session ran `db:drop db:create db:migrate` without
# RAILS_ENV=test and destroyed inventory_app_development. The failure was
# procedural (a missing environment variable), not a code defect - so the
# fix is structural: make that class of mistake impossible without an
# explicit, one-time human override.
#
# This guard checks the ACTUAL RESOLVED database configuration for the
# current Rails.env (respecting DATABASE_URL/config overrides), not just
# string-matching the invoked command. It only blocks when Rails.env is
# development AND the resolved database name is the protected one - a
# development-flavored environment pointed at a different database (e.g.
# via an overridden DATABASE_URL) is correctly left alone.
#
# IMPORTANT FOR AI AGENTS: you may NEVER set ALLOW_DESTRUCTIVE_DEV_DB
# yourself, under any circumstance. See AGENTS.md / CLAUDE.md, the
# "CRITICAL DATABASE SAFETY" section. Only a human, in their own current
# instruction, may authorize destroying the development database.
module DatabaseSafety
  # Every Rake task that would drop, rebuild, or wipe the contents of a
  # database. db:structure:load is kept for older Rails versions even though
  # Rails 8 folds it into db:schema:load - task_defined? below skips it
  # gracefully when it does not exist. db:purge / db:truncate_all empty every
  # table of whatever database the current Rails.env resolves to, which for
  # development is exactly the loss we are preventing; the :all variants do
  # the same across every configured database. The *:reset / migrate:reset
  # variants are covered transitively because they depend on db:drop.
  PROTECTED_TASKS = %w[
    db:drop
    db:drop:all
    db:reset
    db:setup
    db:schema:load
    db:structure:load
    db:purge
    db:purge:all
    db:truncate_all
  ].freeze
  PROTECTED_DATABASE_NAME = 'inventory_app_development'
  OVERRIDE_ENV_VAR = 'ALLOW_DESTRUCTIVE_DEV_DB'
  OVERRIDE_VALUE = 'I_UNDERSTAND_DATA_WILL_BE_LOST'

  module_function

  # The db config Rails would actually use right now for the current
  # Rails.env - this is what a destructive task would really target,
  # regardless of what RAILS_ENV merely says.
  def resolved_db_config
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env.to_s).first
  end

  def targets_protected_database?(config = resolved_db_config)
    return false unless Rails.env.development?
    return false unless config

    config.database.to_s == PROTECTED_DATABASE_NAME
  end

  def override_active?
    ENV[OVERRIDE_ENV_VAR] == OVERRIDE_VALUE
  end

  def describe_target(config)
    hash = config.configuration_hash
    "#{config.database} (host: #{hash[:host] || 'unix socket'}, port: #{hash[:port] || 'default'})"
  end

  # Called as a prerequisite of every task in PROTECTED_TASKS. Aborts the
  # whole process before the destructive task's own action runs, unless the
  # human override is explicitly set.
  def guard!(task_name)
    config = resolved_db_config

    # Fail closed: in development a destructive task must positively prove it
    # is NOT pointed at the protected database before it is allowed through.
    # If the config cannot be resolved we refuse rather than guess.
    abort(unresolved_message(task_name)) if Rails.env.development? && config.nil?

    return unless targets_protected_database?(config)

    if override_active?
      warn <<~WARN
        [db_safety] #{OVERRIDE_ENV_VAR} is set - proceeding with destructive
        task "#{task_name}" against #{describe_target(config)}.
        This must be an explicit human decision made for this exact run.
      WARN
      return
    end

    abort(blocked_message(task_name, config))
  end

  def blocked_message(task_name, config)
    <<~MSG

      ============================================================
       BLOCKED: destructive database task "#{task_name}"
      ============================================================
       Rails.env      : #{Rails.env}
       Target database: #{describe_target(config)}

       "#{task_name}" would drop, reset, or replace the LOCAL
       DEVELOPMENT database (#{PROTECTED_DATABASE_NAME}). This is
       blocked unconditionally by lib/tasks/database_safety.rake.

       Use an isolated database instead, e.g.:
         RAILS_ENV=test #{task_name}

       This can only be overridden by a human operator, in this
       exact terminal session, who has explicitly decided to
       destroy the local development database:

         #{OVERRIDE_ENV_VAR}=#{OVERRIDE_VALUE} #{task_name}

       An AI agent must NEVER set this variable on its own -
       see AGENTS.md / CLAUDE.md, "CRITICAL DATABASE SAFETY".
      ============================================================

    MSG
  end

  def unresolved_message(task_name)
    <<~MSG

      ============================================================
       BLOCKED: destructive database task "#{task_name}"
      ============================================================
       Rails.env      : #{Rails.env}
       Target database: could not be resolved

       Refusing to run a destructive database task in the
       development environment without positively confirming the
       target is not #{PROTECTED_DATABASE_NAME}.

       Load the database configuration (e.g. run via bin/rails, or
       add `:environment` as a prerequisite) and try again, or use
       an isolated database: RAILS_ENV=test #{task_name}
      ============================================================

    MSG
  end
end

namespace :db_safety do
  desc 'Abort if a destructive db task would hit the protected development database (safe pre-flight check)'
  task guard: :environment do
    top_level = Rake.application.top_level_tasks.first
    task_name =
      if top_level.nil? || top_level == 'db_safety:guard'
        'a destructive database task'
      else
        top_level
      end
    DatabaseSafety.guard!(task_name)
  end
end

DatabaseSafety::PROTECTED_TASKS.each do |task_name|
  # db:structure:load does not exist as a separate task on Rails versions
  # where db:schema:load already handles both schema.rb and structure.sql
  # (this app's Rails 8) - skip gracefully rather than erroring on a task
  # that isn't defined.
  Rake::Task[task_name].enhance(['db_safety:guard']) if Rake::Task.task_defined?(task_name)
end

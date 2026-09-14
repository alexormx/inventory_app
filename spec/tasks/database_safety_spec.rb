# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# These specs exercise DatabaseSafety's decision logic directly (stubbing
# Rails.env / ActiveRecord configuration / ENV) rather than ever invoking the
# real destructive db:* rake tasks (db:drop, db:reset, db:setup,
# db:schema:load, db:purge, db:truncate_all). That's deliberate: invoking
# those tasks for real - even to prove they get blocked - would mean their
# prerequisite chain runs against whatever database the *real* process
# resolves to, and a wiring mistake in a test could destroy this repo's
# actual inventory_app_test (or worse) database.
# Testing the pure decision function is both safer and more precise: it
# proves the guard's logic is correct independent of Rake's own prerequisite
# execution order, which is verified separately below via a structural
# (read-only) check of `Rake::Task#prerequisites`.
RSpec.describe 'DatabaseSafety' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('db_safety:guard')
  end

  def fake_config(database:, host: nil, port: nil)
    instance_double(
      ActiveRecord::DatabaseConfigurations::HashConfig,
      database: database,
      configuration_hash: { database: database, host: host, port: port }.compact
    )
  end

  describe '.targets_protected_database?' do
    it 'is true for development pointed at inventory_app_development' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      config = fake_config(database: 'inventory_app_development')

      expect(DatabaseSafety.targets_protected_database?(config)).to be true
    end

    it 'is false for the test environment even with the same-shaped config' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
      config = fake_config(database: 'inventory_app_development')

      expect(DatabaseSafety.targets_protected_database?(config)).to be false
    end

    it 'is false when development resolves to a different database (e.g. an overridden DATABASE_URL)' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      config = fake_config(database: 'some_other_scratch_db')

      expect(DatabaseSafety.targets_protected_database?(config)).to be false
    end

    it 'is false when no config resolves at all' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

      expect(DatabaseSafety.targets_protected_database?(nil)).to be false
    end

    it 'reflects the real current test environment as not protected' do
      # No stubbing here - this proves resolved_db_config genuinely resolves
      # the actual database configuration for the process running the spec
      # suite, not a hardcoded assumption.
      expect(Rails.env.test?).to be true
      expect(DatabaseSafety.targets_protected_database?).to be false
      expect(DatabaseSafety.resolved_db_config.database).to eq('inventory_app_test')
    end
  end

  describe '.override_active?' do
    it 'is false when the override env var is unset' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ALLOW_DESTRUCTIVE_DEV_DB').and_return(nil)

      expect(DatabaseSafety.override_active?).to be false
    end

    it 'is false for a near-miss value (must match exactly)' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ALLOW_DESTRUCTIVE_DEV_DB').and_return('true')

      expect(DatabaseSafety.override_active?).to be false
    end

    it 'is true only for the exact required phrase' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ALLOW_DESTRUCTIVE_DEV_DB').and_return('I_UNDERSTAND_DATA_WILL_BE_LOST')

      expect(DatabaseSafety.override_active?).to be true
    end
  end

  describe '.guard!' do
    it 'aborts (without running anything) when targeting development inventory_app_development' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'inventory_app_development'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      allow(DatabaseSafety).to receive(:override_active?).and_return(false)

      expect { DatabaseSafety.guard!('db:drop') }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
    end

    it 'includes the task name and target database in the abort message' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'inventory_app_development'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      allow(DatabaseSafety).to receive(:override_active?).and_return(false)

      message = nil
      allow(DatabaseSafety).to receive(:abort) { |msg| message = msg; raise SystemExit }

      expect { DatabaseSafety.guard!('db:schema:load') }.to raise_error(SystemExit)
      expect(message).to include('db:schema:load', 'inventory_app_development', 'RAILS_ENV=test',
                                  'ALLOW_DESTRUCTIVE_DEV_DB=I_UNDERSTAND_DATA_WILL_BE_LOST')
    end

    it 'does not abort for a non-development environment' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'inventory_app_development'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))

      expect { DatabaseSafety.guard!('db:drop') }.not_to raise_error
    end

    it 'does not abort for development pointed at a different database' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'some_other_db'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

      expect { DatabaseSafety.guard!('db:drop') }.not_to raise_error
    end

    it 'fails closed: aborts in development when the target database cannot be resolved' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

      message = nil
      allow(DatabaseSafety).to receive(:abort) { |msg| message = msg; raise SystemExit }

      expect { DatabaseSafety.guard!('db:drop') }.to raise_error(SystemExit)
      expect(message).to include('db:drop', 'could not be resolved')
    end

    it 'does not fail closed outside development when the config cannot be resolved' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))

      expect { DatabaseSafety.guard!('db:drop') }.not_to raise_error
    end

    it 'proceeds (with a warning, not an abort) when the human override is active' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'inventory_app_development'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      allow(DatabaseSafety).to receive(:override_active?).and_return(true)
      allow(DatabaseSafety).to receive(:warn)

      expect { DatabaseSafety.guard!('db:drop') }.not_to raise_error
      expect(DatabaseSafety).to have_received(:warn)
    end

    it 'never calls abort when the override is active, even though the target is protected' do
      allow(DatabaseSafety).to receive(:resolved_db_config).and_return(fake_config(database: 'inventory_app_development'))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      allow(DatabaseSafety).to receive(:override_active?).and_return(true)
      allow(DatabaseSafety).to receive(:warn)
      allow(DatabaseSafety).to receive(:abort)

      DatabaseSafety.guard!('db:drop')

      expect(DatabaseSafety).not_to have_received(:abort)
    end
  end

  describe 'rake task wiring (structural, read-only - never invokes the tasks)' do
    it 'enhances every defined protected task with db_safety:guard as a prerequisite' do
      # db:structure:load is intentionally absent on Rails 8 - see the
      # dedicated example below.
      %w[db:drop db:drop:all db:reset db:setup db:schema:load
         db:purge db:purge:all db:truncate_all].each do |task_name|
        expect(Rake::Task[task_name].prerequisites).to include('db_safety:guard'),
                                                        "expected #{task_name} to depend on db_safety:guard"
      end
    end

    it 'does not exist for db:structure:load on this Rails version (db:schema:load covers both formats)' do
      expect(Rake::Task.task_defined?('db:structure:load')).to be false
    end

    it 'makes the db_safety:guard pre-flight task self-sufficient by depending on :environment' do
      expect(Rake::Task['db_safety:guard'].prerequisites).to include('environment')
    end

    it 'leaves db:migrate unaffected' do
      expect(Rake::Task['db:migrate'].prerequisites).not_to include('db_safety:guard')
    end

    it 'leaves db:migrate:status unaffected' do
      expect(Rake::Task['db:migrate:status'].prerequisites).not_to include('db_safety:guard')
    end

    it 'leaves db:test:prepare unaffected so the test database keeps working normally' do
      expect(Rake::Task['db:test:prepare'].prerequisites).not_to include('db_safety:guard')
    end

    it 'lists exactly the specified destructive tasks as protected, regardless of which are actually defined' do
      expect(DatabaseSafety::PROTECTED_TASKS).to contain_exactly(
        'db:drop', 'db:drop:all', 'db:reset', 'db:setup', 'db:schema:load',
        'db:structure:load', 'db:purge', 'db:purge:all', 'db:truncate_all'
      )
    end
  end
end

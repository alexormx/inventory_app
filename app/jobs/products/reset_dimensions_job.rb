module Products
	class ResetDimensionsJob < ApplicationJob
		queue_as :default

		DEFAULTS = {
			weight_gr: 50.0,
			length_cm: 8.0,
			width_cm: 4.0,
			height_cm: 4.0
		}.freeze

		def perform(run_id)
			run = MaintenanceRun.find_by(id: run_id)
			updated = 0
			total = Product.count
			Product.find_each(batch_size: 100) do |p|
				attrs = {}
				DEFAULTS.each do |k, v|
					current = p.send(k)
					if current.nil? || current.to_f <= 0
						attrs[k] = v
					end
				end
				if attrs.any?
						p.update_columns(attrs) # evita callbacks pesados
						updated += 1
				end
			end
			if run
				run.update!(status: :completed, finished_at: Time.current, stats: { total: total, updated: updated }.to_json)
			end
		rescue => e
			run.update!(status: :failed, finished_at: Time.current, error: "#{e.class}: #{e.message}") if run
			Rails.logger.error("ResetDimensionsJob error: #{e.class} #{e.message}")
			raise
		end
	end
end


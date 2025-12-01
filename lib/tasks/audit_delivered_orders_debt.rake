# frozen_string_literal: true

namespace :audit do
  desc 'Audita órdenes Delivered con adeudo (uso: rake audit:delivered_debt[auto_fix,create_payments])'
  task :delivered_debt, %i[auto_fix create_payments] => :environment do |_, args|
    auto_fix = ActiveModel::Type::Boolean.new.cast(args[:auto_fix])
    create_payments = ActiveModel::Type::Boolean.new.cast(args[:create_payments])
    auditor = Audit::DeliveredOrdersDebtAudit.new(auto_fix: auto_fix, create_payments: create_payments)
    result = auditor.run
    puts "Total Delivered: #{result.total_orders}"
    puts "Con adeudo: #{result.with_debt}"
    puts "Adeudo total: #{result.total_debt_amount}"
    if result.details.any?
      puts 'Detalles:'.dup
      result.details.each do |d|
        puts "- SO=#{d[:sale_order_id]} user=#{d[:user_id]} total=#{d[:total_order_value]} pagado=#{d[:total_paid]} falta=#{d[:missing_amount]} fixed=#{d[:fixed]} error=#{d[:error]}"
      end
    end
  end
end

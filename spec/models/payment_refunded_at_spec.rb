require 'rails_helper'

RSpec.describe Payment, 'refunded_at' do
  let(:payment) { create(:payment, status: 'Completed', amount: 100) }

  it 'fija refunded_at con la fecha de hoy al pasar a Refunded' do
    travel_to(Time.zone.local(2026, 3, 31, 12)) { payment.update!(status: 'Refunded') }
    expect(payment.reload.refunded_at).to eq(Date.new(2026, 3, 31))
  end

  it 'no sobrescribe un refunded_at existente' do
    payment.update!(status: 'Refunded', refunded_at: Date.new(2026, 1, 5))
    payment.update!(amount: 90)
    expect(payment.reload.refunded_at).to eq(Date.new(2026, 1, 5))
  end

  it 'limpia refunded_at al salir de Refunded y usa la nueva fecha en un segundo reembolso' do
    travel_to(Time.zone.local(2026, 3, 31, 12)) { payment.update!(status: 'Refunded') }
    payment.update!(status: 'Completed')
    expect(payment.reload.refunded_at).to be_nil

    travel_to(Time.zone.local(2026, 5, 10, 12)) { payment.update!(status: 'Refunded') }
    expect(payment.reload.refunded_at).to eq(Date.new(2026, 5, 10))
  end

  it 'deja refunded_at vacío en pagos no reembolsados' do
    expect(payment.refunded_at).to be_nil
  end
end

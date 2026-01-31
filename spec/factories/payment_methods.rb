# frozen_string_literal: true

FactoryBot.define do
  factory :payment_method do
    sequence(:name) { |n| "Método de Pago #{n}" }
    sequence(:code) { |n| "payment_#{n}" }
    description { "Descripción del método de pago" }
    instructions { "Instrucciones de pago" }
    active { true }
    position { 0 }

    trait :transferencia_bancaria do
      name { "Transferencia / Depósito Bancario" }
      code { "transferencia_bancaria" }
      description { "Pago mediante transferencia o depósito bancario" }
      instructions { "Realiza tu pago a la cuenta indicada" }
      bank_name { "BBVA" }
      account_holder { "Pasatiempos SA de CV" }
      account_number { "012345678901234567" }
    end

    trait :oxxo do
      name { "Depósito en OXXO" }
      code { "oxxo" }
      description { "Pago en efectivo en tiendas OXXO" }
      instructions { "Presenta el código de barras en cualquier OXXO" }
      account_number { "4152 3138 1234 5678" }
    end

    trait :tarjeta do
      name { "Tarjeta de Crédito/Débito" }
      code { "tarjeta" }
      description { "Pago con tarjeta" }
      instructions { "Se procesará al confirmar el pedido" }
    end

    trait :inactive do
      active { false }
    end
  end
end

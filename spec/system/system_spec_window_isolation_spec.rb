# frozen_string_literal: true

require 'rails_helper'

# Fija el aislamiento del viewport. Sin esto, un spec responsive dejaba la
# ventana en 390x844 o 1024x768 y el siguiente ejemplo la heredaba, así que con
# config.order = :random la suite completa fallaba en CI en un spec distinto
# cada vez. Si alguien quita el resize del hook, esto se pone rojo aquí y no
# tres semanas después en un spec que no tiene nada que ver.
RSpec.describe 'System spec window isolation', :js, type: :system do
  it 'arranca cada ejemplo en el escritorio canónico' do
    expect(page.current_window.size).to eq(SYSTEM_SPEC_WINDOW_SIZE)
  end

  context 'después de que un ejemplo encoja la ventana' do
    it 'encoge la ventana a un móvil' do
      page.current_window.resize_to(390, 844)

      expect(page.current_window.size).to eq([390, 844])
    end

    it 'vuelve al escritorio canónico en el ejemplo siguiente' do
      expect(page.current_window.size).to eq(SYSTEM_SPEC_WINDOW_SIZE)
    end
  end
end

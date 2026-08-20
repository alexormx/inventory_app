# frozen_string_literal: true

require 'rails_helper'

# Fija la traducción del error de nodo desprendido. Si Capybara o Selenium
# cambian de forma, esto avisa antes de que la suite de sistema vuelva a ponerse
# roja en CI sin explicación.
RSpec.describe DetachedNodeSynchronization do
  def unknown_error(message)
    Selenium::WebDriver::Error::UnknownError.new(message)
  end

  # El payload exacto que devuelve chromedriver cuando el nodo ya no está.
  let(:cdp_detached) do
    'unknown error: unhandled inspector error: ' \
      '{"code":-32000,"message":"Node with given id does not belong to the document"}'
  end

  it 'reetiqueta como stale el UnknownError con el payload de CDP de Chrome' do
    expect do
      described_class.translating { raise unknown_error(cdp_detached) }
    end.to raise_error(Selenium::WebDriver::Error::StaleElementReferenceError, /does not belong to the document/)
  end

  it 'deja pasar intacto cualquier otro UnknownError' do
    other = unknown_error('unknown error: session deleted because of page crash')

    expect do
      described_class.translating { raise other }
    end.to raise_error(Selenium::WebDriver::Error::UnknownError, /page crash/)
  end

  it 'no toca los errores que no son de Selenium' do
    expect do
      described_class.translating { raise ArgumentError, 'boom' }
    end.to raise_error(ArgumentError, 'boom')
  end

  it 'devuelve el valor del bloque cuando no hay error' do
    expect(described_class.translating { :ok }).to eq(:ok)
  end

  # Que la traducción funcione no sirve de nada si el módulo no quedó instalado
  # delante de la clase que de verdad toca el navegador.
  it 'queda instalado delante de Capybara::Selenium::Node' do
    wrapper = Capybara::Selenium::Node.ancestors.find do |mod|
      mod.instance_of?(Module) && mod.instance_methods(false).include?(:click)
    end

    expect(wrapper).not_to be_nil
  end

  # El reintento que queremos recuperar es el que Capybara ya tiene: si el error
  # traducido no estuviera en invalid_element_errors, la traducción no serviría.
  it 'produce un error que Capybara sí reintenta' do
    driver = Capybara::Selenium::Driver.allocate

    expect(driver.invalid_element_errors)
      .to include(Selenium::WebDriver::Error::StaleElementReferenceError)
  end
end

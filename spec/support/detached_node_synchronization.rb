# frozen_string_literal: true

require 'capybara/selenium/driver'
require 'capybara/selenium/node'

# Traduce el error de nodo desprendido que Chrome moderno reporta mal.
#
# El W3C dice que tocar un elemento que ya no está en el documento debe fallar
# con StaleElementReferenceError. Chrome >= ~130 lo reporta como un
# UnknownError genérico que sólo lleva el payload crudo de CDP:
#
#   unknown error: unhandled inspector error:
#   {"code":-32000,"message":"Node with given id does not belong to the document"}
#
# Capybara ya sabe sincronizar los nodos desprendidos: Node::Base#synchronize
# reintenta dentro de default_max_wait_time cualquier error listado en
# driver#invalid_element_errors, y StaleElementReferenceError está en esa lista.
# Pero catch_error? compara con is_a?, así que el error mal etiquetado se escapa
# del reintento y tumba el ejemplo en el primer intento.
#
# Eso es exactamente lo que puso en rojo la suite completa de sistema en CI
# (Chrome 151) mientras en local seguía verde (Chromium 108, que sí levanta el
# error correcto): fallaba siempre en location_first_bulk_assignment_spec, pero
# en un ejemplo distinto cada vez, según qué recarga ganara la carrera.
#
# Aquí NO se añade un reintento nuevo ni se relaja ninguna aserción: sólo se le
# pone al error la etiqueta que le corresponde para que actúe la sincronización
# que Capybara ya implementa. Cualquier otro UnknownError sigue fallando al
# instante, y un nodo que de verdad nunca se estabiliza sigue fallando al
# agotarse la espera.
module DetachedNodeSynchronization
  DETACHED_NODE_MESSAGE = 'does not belong to the document'

  def self.translating(&block)
    block.call
  rescue ::Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.include?(DETACHED_NODE_MESSAGE)

    raise ::Selenium::WebDriver::Error::StaleElementReferenceError, e.message
  end

  # En el nodo se envuelven los métodos realmente declarados en la clase, no una
  # lista escrita a mano: ahí vive toda la interacción con el elemento, así que
  # un cambio de Capybara no debe dejar huecos silenciosos.
  def self.wrap(klass, only: nil)
    names = klass.public_instance_methods(false)
    names &= only if only
    wrapper = Module.new do
      names.each do |name|
        define_method(name) do |*args, **kwargs, &blk|
          DetachedNodeSynchronization.translating do
            super(*args, **kwargs, &blk)
          end
        end
      end
    end
    klass.prepend(wrapper)
  end

  # Del driver sólo interesan las entradas que consultan el documento; envolver
  # también quit/reset! sólo añadiría ruido en el teardown.
  DRIVER_METHODS = %i[find_css find_xpath evaluate_script evaluate_async_script execute_script].freeze
end

DetachedNodeSynchronization.wrap(Capybara::Selenium::Node)
DetachedNodeSynchronization.wrap(Capybara::Selenium::Driver, only: DetachedNodeSynchronization::DRIVER_METHODS)

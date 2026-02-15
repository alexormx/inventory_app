# frozen_string_literal: true

class HealthController < ApplicationController
  # Endpoint ligero para chequeo de vida. No hereda de ApplicationController
  # para evitar callbacks y accesos a BD innecesarios durante arranque.
  def show
    render plain: 'OK', status: :ok
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Cobertura BLOQUEANTE y determinista del cierre de sesión.
#
# El recorrido equivalente por navegador real (login -> perfil -> click en
# "Cerrar sesión") está en cuarentena en spec/system/user_login_spec.rb porque
# Chrome puede aceptar la entrada sin entregarla; ver
# .github/workflows/browser-input-diagnostic.yml. Estos ejemplos cubren lo que
# aquella prueba garantizaba de la APLICACIÓN, sin depender de la entrega de
# eventos del navegador: la semántica de la sesión y la existencia y
# configuración de los dos controles reales de logout.
RSpec.describe 'User session lifecycle', type: :request do
  let(:password) { 'password123' }
  let!(:user) { create(:user, email: 'user@example.com', password: password) }

  describe 'signing in and out' do
    it 'authenticates, serves an authenticated route, and destroys the session on sign out' do
      post user_session_path, params: { user: { email: user.email, password: password } }
      expect(response).to be_redirect

      get profile_path
      expect(response).to have_http_status(:ok)

      delete destroy_user_session_path
      expect(response).to be_redirect
      expect(flash[:notice]).to eq('Sesión finalizada.')

      get profile_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'does not authenticate with an invalid password' do
      post user_session_path, params: { user: { email: user.email, password: 'wrongpassword' } }

      get profile_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  # Los dos controles existen en sitios distintos y por razones distintas: el
  # de la barra vive dentro del desplegable de cuenta, y el de la tarjeta de
  # perfil se añadió justamente porque quien no encontrara el desplegable no
  # tenía forma de salir. Se comprueban los dos para que ninguno pueda
  # desaparecer sin que falle nada.
  describe 'the rendered logout controls' do
    before do
      post user_session_path, params: { user: { email: user.email, password: password } }
      get profile_path
    end

    it 'renders the profile logout control as a DELETE to the Devise route' do
      expect(response.body).to include('Cerrar sesión')

      form = Nokogiri::HTML(response.body).css('form[action="/users/sign_out"]').first
      expect(form).to be_present
      expect(form['method']).to eq('post')
      expect(form.css('input[name="_method"]').first['value']).to eq('delete')
    end

    it 'renders the navbar dropdown logout control inside the account menu' do
      doc = Nokogiri::HTML(response.body)

      button = doc.css('#account-menu #logout-button').first
      expect(button).to be_present
      expect(button.text).to include('Cerrar sesión')
      expect(button.ancestors('form').first['action']).to eq(destroy_user_session_path)
    end

    it 'exposes both logout controls, so neither can be removed silently' do
      forms = Nokogiri::HTML(response.body).css('form[action="/users/sign_out"]')
      expect(forms.size).to eq(2)
    end
  end
end

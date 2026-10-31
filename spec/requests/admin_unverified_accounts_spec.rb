# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin unverified accounts', type: :request do
  let(:admin) { create(:user, :admin) }

  def self_registered(email:, created_at: Time.current, **attrs)
    create(:user, email: email, self_registered: true, confirmed_at: nil,
                  created_at: created_at, confirmation_sent_at: created_at, **attrs)
  end

  describe 'public sign-up' do
    it 'marks the account as self-registered and unverified' do
      post user_registration_path, params: {
        user: { email: 'nuevo@example.com', password: 'secreto123', password_confirmation: 'secreto123' }
      }

      user = User.find_by!(email: 'nuevo@example.com')
      expect(user).to be_self_registered
      expect(user.confirmed_at).to be_nil
      expect(User.unverified_self_registered).to include(user)
    end
  end

  describe 'scopes' do
    it 'leaves out admin-created, confirmed and anonymized accounts' do
      waiting = self_registered(email: 'espera@example.com')
      old = self_registered(email: 'vieja@example.com', created_at: 3.days.ago)
      create(:user, email: 'admin-creado@example.com', confirmed_at: nil, self_registered: false)
      create(:user, email: 'confirmada@example.com', self_registered: true)
      self_registered(email: "x@#{User::ANONYMIZED_EMAIL_DOMAIN}", created_at: 3.days.ago)

      expect(User.unverified_self_registered).to contain_exactly(waiting, old)
      expect(User.unverified_needing_review).to contain_exactly(old)
    end
  end

  describe 'admin page' do
    before { sign_in admin }

    it 'lists pending accounts with their review state' do
      self_registered(email: 'espera@example.com')
      self_registered(email: 'vieja@example.com', created_at: 3.days.ago)
      create(:user, email: 'admin-creado@example.com', confirmed_at: nil)

      get admin_unverified_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('espera@example.com', 'vieja@example.com', 'En revisión: 1')
      expect(response.body).not_to include('admin-creado@example.com')
    end

    it 'resends the confirmation email' do
      user = self_registered(email: 'vieja@example.com', created_at: 3.days.ago)

      # spec_helper stubs send_confirmation_instructions for every User, so
      # assert the call instead of counting deliveries.
      expect_any_instance_of(User).to receive(:send_confirmation_instructions).once # rubocop:disable RSpec/AnyInstance

      post resend_confirmation_admin_unverified_account_path(user)

      expect(response).to redirect_to(admin_unverified_accounts_path)
      expect(flash[:notice]).to include('vieja@example.com')
    end

    it 'confirms the account by hand' do
      user = self_registered(email: 'vieja@example.com', created_at: 3.days.ago)

      post confirm_admin_unverified_account_path(user)

      expect(user.reload.confirmed_at).to be_present
      expect(User.unverified_self_registered).not_to include(user)
    end

    it 'does not act on accounts that are not pending' do
      user = create(:user, email: 'confirmada@example.com', self_registered: true)

      post confirm_admin_unverified_account_path(user)

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'is not available to customers' do
    sign_in create(:user)

    get admin_unverified_accounts_path

    expect(response).not_to have_http_status(:ok)
  end
end

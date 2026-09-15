# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::AuthenticationHandoff do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:session_id) { SecureRandom.hex(16) }

  # A stand-in for ActionDispatch::Request::Session: hash access plus #id.
  def build_session(cart, id: session_id)
    Class.new(Hash) do
      attr_accessor :public_id

      def id
        public_id && Rack::Session::SessionId.new(public_id)
      end
    end.new.tap do |s|
      s.public_id = id
      s[:cart] = cart unless cart.nil?
    end
  end

  def logged
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  it 'imports the browser cart and rewrites the session with the reconciled contents' do
    session = build_session({ product.id.to_s => { 'brand_new' => 2 } })

    result = described_class.call(user: user, session: session)

    expect(result.status).to eq(:imported)
    expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
    expect(session[described_class::MARKER_KEY]).to eq(result.session_marker)
    expect(session[described_class::MARKER_KEY]).to include('cart_id' => result.cart.id)
    expect(CartSessionImport.sole.import_key_digest).to eq(ShoppingCarts::ImportIdentity.new(session_id).digest)
  end

  it 'leaves the session untouched when the result carries nothing to hydrate' do
    session = build_session({ product.id.to_s => { 'brand_new' => 'nope' } })

    result = described_class.call(user: user, session: session)

    expect(result.status).to eq(:invalid_payload)
    expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 'nope' })
    expect(session).not_to have_key(described_class::MARKER_KEY)
  end

  it 'does not import when the session has no id yet' do
    session = build_session({ product.id.to_s => { 'brand_new' => 1 } }, id: nil)

    expect(described_class.call(user: user, session: session).status).to eq(:missing_identity)
    expect(ShoppingCart.count).to eq(0)
  end

  it 'swallows and logs any failure so authentication continues' do
    allow(ShoppingCarts::SessionReconciler).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'db gone')
    session = build_session({ product.id.to_s => { 'brand_new' => 1 } })

    output = nil
    expect { output = logged { described_class.call(user: user, session: session) } }.not_to raise_error
    expect(output).to include('ActiveRecord::StatementInvalid').and include("user_id=#{user.id}")
    expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
  end

  it 'never logs the session id, the import key, the receipt digests or the payload' do
    session = build_session({ product.id.to_s => { 'brand_new' => 2 } })
    identity = ShoppingCarts::ImportIdentity.new(session_id)

    output = logged { described_class.call(user: user, session: session) }

    expect(output).to include('status=imported')
    expect(output).not_to include(session_id)
    expect(output).not_to include(identity.import_key)
    expect(output).not_to include(identity.digest)
    expect(output).not_to include(CartSessionImport.sole.source_payload_digest)
    expect(output).not_to include(session[described_class::MARKER_KEY]['digest'])
    expect(output).not_to include('brand_new')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin collectible AI lookups', type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }
  let(:png) { Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png') }

  before { sign_in admin }

  describe 'POST create' do
    it 'crea la búsqueda y la encola' do
      expect do
        post admin_collectible_ai_lookups_path, params: { photo: png }
      end.to have_enqueued_job(Collectibles::AiLookupJob)

      expect(response).to have_http_status(:created)
      lookup = Collectibles::AiLookup.last
      expect(response.parsed_body).to eq('id' => lookup.id, 'status_url' => admin_collectible_ai_lookup_path(lookup))
      expect(lookup.user).to eq(admin)
    end

    it 'rechaza un HEIC sin gastar' do
      heic = Rack::Test::UploadedFile.new(StringIO.new('heic'), 'image/heic', original_filename: 'IMG_0001.HEIC')
      expect { post admin_collectible_ai_lookups_path, params: { photo: heic } }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('JPG, PNG, WEBP o GIF')
    end

    it 'rechaza la petición sin foto' do
      post admin_collectible_ai_lookups_path
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'respeta el límite diario' do
      allow(Collectibles::AiLookup).to receive(:daily_limit_reached?).and_return(true)
      expect { post admin_collectible_ai_lookups_path, params: { photo: png } }.not_to have_enqueued_job

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to include('límite')
    end

    it 'no deja entrar a un cliente' do
      sign_in create(:user)
      post admin_collectible_ai_lookups_path, params: { photo: png }
      expect(response).to redirect_to(root_path)
      expect(Collectibles::AiLookup.count).to eq(0)
    end
  end

  describe 'GET show' do
    def create_lookup(user)
      Collectibles::AiLookup.new(user: user).tap do |l|
        l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
        l.save!
      end
    end

    it 'devuelve el estado de una búsqueda propia' do
      lookup = create_lookup(admin)
      lookup.update!(status: :done, result: { 'identification' => { 'brand' => 'Tomica' } })

      get admin_collectible_ai_lookup_path(lookup)
      expect(response.parsed_body).to include('status' => 'done')
      expect(response.parsed_body.dig('result', 'identification', 'brand')).to eq('Tomica')
    end

    it 'no muestra la búsqueda de otro admin' do
      other = create_lookup(create(:user, :admin))
      get admin_collectible_ai_lookup_path(other)
      expect(response).to have_http_status(:not_found)
    end

    it 'reporta como fallida una búsqueda atorada' do
      lookup = create_lookup(admin)
      lookup.update!(status: :running)
      travel 4.minutes do
        get admin_collectible_ai_lookup_path(lookup)
        expect(response.parsed_body['status']).to eq('failed')
      end
    end
  end
end

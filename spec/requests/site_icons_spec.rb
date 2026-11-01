# frozen_string_literal: true

require 'rails_helper'

# Safari, iOS y los lectores de feeds piden estos iconos en la raíz sin mirar
# el <head>; sin archivo en public/ cada visita deja un 404 en los logs.
RSpec.describe 'Site icons', type: :request do
  %w[/favicon.ico /apple-touch-icon.png /apple-touch-icon-precomposed.png].each do |path|
    it "serves #{path} from public/" do
      file = Rails.public_path.join(path.delete_prefix('/'))

      expect(file).to exist
      expect(file.size).to be_positive
    end
  end

  it 'points the apple-touch-icon link at the real PNG' do
    get root_path

    expect(response.body).to include('<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">')
  end
end

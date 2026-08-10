# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'

RSpec.describe 'images:responsive_convert' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('images:responsive_convert')
  end

  let(:task) { Rake::Task['images:responsive_convert'] }

  after { task.reenable }

  it 'generates responsive variants with keyword saver options' do
    Dir.mktmpdir do |directory|
      image_dir = Pathname(directory)
      FileUtils.cp(Rails.root.join('spec/fixtures/files/test1.png'), image_dir.join('collection_shelf.jpg'))
      stub_const('IMAGE_DIR', image_dir)
      stub_const('RESPONSIVE_WIDTHS', [64].freeze)

      task.invoke

      generated = {
        jpg: image_dir.join('collection_shelf-64w.jpg'),
        webp: image_dir.join('collection_shelf-64w.webp')
      }
      results = generated.transform_values do |path|
        image = Vips::Image.new_from_file(path.to_s)
        { width: image.width, loader: image.get('vips-loader'), size: File.size(path) }
      end

      expect(results).to match(
        jpg: { width: 64, loader: 'jpegload', size: be_positive },
        webp: { width: 64, loader: 'webpload', size: be_positive }
      )
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OpenAI initializer" do
  subject(:load_initializer) { load Rails.root.join("config/initializers/openai.rb") }

  let(:configuration) do
    double("OpenAI configuration", "access_token=" => nil, "request_timeout=" => nil)
  end

  before do
    @original_api_key = ENV["OPENAI_API_KEY"]
    allow(OpenAI).to receive(:configure).and_yield(configuration)
  end

  after { ENV["OPENAI_API_KEY"] = @original_api_key }

  context "when OPENAI_API_KEY is present" do
    it "uses the environment value without reading encrypted credentials" do
      ENV["OPENAI_API_KEY"] = "env-openai-key"

      expect(Rails.application).not_to receive(:credentials)
      expect(configuration).to receive(:access_token=).with("env-openai-key")

      expect { load_initializer }.not_to output.to_stdout
    end
  end

  context "when OPENAI_API_KEY is absent" do
    before { ENV.delete("OPENAI_API_KEY") }

    it "uses the existing openai.api_key credentials value" do
      credentials = double("Rails credentials")
      allow(Rails.application).to receive(:credentials).and_return(credentials)
      expect(credentials).to receive(:dig).with(:openai, :api_key).and_return("credentials-openai-key")
      expect(configuration).to receive(:access_token=).with("credentials-openai-key")

      load_initializer
    end

    it "leaves optional OpenAI features unconfigured without breaking initialization" do
      credentials = double("Rails credentials", dig: nil)
      allow(Rails.application).to receive(:credentials).and_return(credentials)
      expect(configuration).to receive(:access_token=).with(nil)
      expect(configuration).to receive(:request_timeout=).with(60)

      expect { load_initializer }.not_to output.to_stdout
    end
  end
end

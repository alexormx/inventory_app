# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::LivePriceService do
  # Sustituto del objeto request de Faraday: el servicio solo escribe headers,
  # params y timeouts sobre él.
  let(:request_class) do
    Class.new do
      attr_reader :headers, :params, :options

      def initialize
        @headers = {}
        @params = {}
        @options = Struct.new(:timeout, :open_timeout).new
      end
    end
  end

  let(:connection) { instance_double(Faraday::Connection) }
  let(:logger) { Logger.new(File::NULL) }

  def stub_get(&block)
    allow(connection).to receive(:get) do |_url, &request_block|
      request = request_class.new
      request_block&.call(request)
      block.call(request)
    end
  end

  def response(payload, success: true)
    instance_double(Faraday::Response, success?: success, status: success ? 200 : 500, body: payload.to_json)
  end

  it "asks for every SKU in a single request when they fit in one batch" do
    requested = []
    stub_get do |request|
      requested << request.params["item_codes"]
      response({ "A1" => { "JPYprice" => "1000" }, "A2" => { "JPYprice" => "2000" } })
    end

    result = described_class.new(connection: connection, logger: logger).call(%w[A1 A2])

    expect(connection).to have_received(:get).once
    expect(requested).to eq(["A1,A2"])
    expect(result["A1"]["JPYprice"]).to eq("1000")
    expect(result.failed_skus).to be_empty
  end

  it "splits the SKUs into batches of the configured size" do
    stub_get { |_request| response({}) }

    described_class.new(connection: connection, batch_size: 2, logger: logger).call(%w[A1 A2 A3 A4 A5])

    expect(connection).to have_received(:get).exactly(3).times
  end

  it "reports a failed batch instead of raising so the sync can continue" do
    stub_get do |request|
      raise Faraday::TimeoutError if request.params["item_codes"] == "B1"

      response({ "A1" => {} })
    end

    result = described_class.new(connection: connection, batch_size: 1, logger: logger).call(%w[A1 B1])

    expect(result.failed_skus).to eq(["B1"])
    expect(result.fetched?("A1")).to be true
    expect(result.fetched?("B1")).to be false
  end

  it "does not report a SKU as fetched when the response omits it" do
    stub_get { |_request| response({ "A1" => { "JPYprice" => "1000" } }) }

    result = described_class.new(connection: connection, logger: logger).call(%w[A1 A2])

    expect(result.fetched?("A1")).to be true
    expect(result.fetched?("A2")).to be false
    expect(result["A2"]).to be_nil
  end

  it "makes no request when there are no SKUs" do
    allow(connection).to receive(:get)

    result = described_class.new(connection: connection, logger: logger).call([])

    expect(connection).not_to have_received(:get)
    expect(result.prices).to eq({})
  end
end

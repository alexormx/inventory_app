# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::SessionCartNormalizer do
  def normalize(raw)
    described_class.call(raw)
  end

  describe 'empty and absent carts' do
    it 'treats a missing session cart as valid and empty' do
      result = normalize(nil)
      expect(result).to be_valid
      expect(result).to be_empty
      expect(result.payload).to eq({})
      expect(result.digest).to be_a(String)
    end

    it 'treats an empty hash as valid and empty' do
      expect(normalize({})).to be_valid.and be_empty
    end

    it 'treats a product with no positive quantities as empty, like Cart#build_items' do
      result = normalize('7' => { 'brand_new' => 0, 'misb' => nil, 'moc' => -3 })
      expect(result).to be_valid
      expect(result).to be_empty
    end
  end

  describe 'valid carts' do
    it 'normalizes the live storefront shape into typed lines and a canonical payload' do
      result = normalize('12' => { 'brand_new' => 2, 'misb' => 1 }, '3' => { 'loose' => 1 })

      expect(result).to be_valid
      expect(result.lines).to contain_exactly(
        have_attributes(product_reference: 3, condition: 'loose', quantity: 1),
        have_attributes(product_reference: 12, condition: 'brand_new', quantity: 2),
        have_attributes(product_reference: 12, condition: 'misb', quantity: 1)
      )
      expect(result.payload).to eq('3' => { 'loose' => 1 }, '12' => { 'brand_new' => 2, 'misb' => 1 })
      expect(result.payload.keys).to eq(%w[3 12])
      expect(result.payload['12'].keys).to eq(%w[brand_new misb])
    end

    it 'migrates the legacy flat format to brand_new exactly like Cart#initialize' do
      result = normalize('5' => 2)
      expect(result.payload).to eq('5' => { 'brand_new' => 2 })
    end

    it 'accepts integer and symbol keys and canonical numeric strings' do
      result = normalize(5 => { misb: 1 }, '9' => { 'brand_new' => '2' })
      expect(result.payload).to eq('5' => { 'misb' => 1 }, '9' => { 'brand_new' => 2 })
    end

    it 'keeps several conditions of the same product as independent lines' do
      result = normalize('4' => { 'brand_new' => 1, 'mib' => 1, 'good' => 1 })
      expect(result.lines.map(&:condition)).to eq(%w[brand_new mib good])
    end

    it 'accepts the technical maximum quantity' do
      expect(normalize('4' => { 'brand_new' => 100_000 })).to be_valid
    end
  end

  describe 'canonical digest' do
    it 'is stable for the same logical cart regardless of insertion order or representation' do
      a = normalize('12' => { 'brand_new' => 2, 'misb' => 1 }, '3' => { 'loose' => 1 })
      b = normalize(3 => { loose: '1' }, '12' => { 'misb' => 1, 'brand_new' => 2 })

      expect(a.digest).to eq(b.digest)
      expect(a.digest).to match(/\A\h{64}\z/)
    end

    it 'changes when any quantity, condition or product changes' do
      base = normalize('12' => { 'brand_new' => 2 })

      expect(normalize('12' => { 'brand_new' => 3 }).digest).not_to eq(base.digest)
      expect(normalize('12' => { 'misb' => 2 }).digest).not_to eq(base.digest)
      expect(normalize('13' => { 'brand_new' => 2 }).digest).not_to eq(base.digest)
    end

    it 'ignores lines that normalize away' do
      expect(normalize('12' => { 'brand_new' => 2, 'misb' => 0 }).digest)
        .to eq(normalize('12' => { 'brand_new' => 2 }).digest)
    end
  end

  describe 'malformed carts invalidate the whole payload' do
    it 'rejects a non-hash cart' do
      expect(normalize('nope')).not_to be_valid
      expect(normalize([['1', { 'brand_new' => 1 }]])).not_to be_valid
    end

    it 'rejects malformed product ids' do
      ['abc', '007', '0', '-4', '', nil, 1.5, 0, -1].each do |bad|
        expect(normalize(bad => { 'brand_new' => 1 })).not_to be_valid, "expected #{bad.inspect} to be rejected"
      end
    end

    it 'rejects unknown conditions, including numeric forms of the enum' do
      %w[sealed 1 BRAND_NEW].each do |bad|
        expect(normalize('4' => { bad => 1 })).not_to be_valid, "expected #{bad.inspect} to be rejected"
      end
      expect(normalize('4' => { 1 => 1 })).not_to be_valid
    end

    it 'rejects quantities Ruby could coerce but a customer never built' do
      [2.0, 2.7, '2.5', '2abc', 'abc', ' 2', '+2', true, [2], { 'n' => 2 }].each do |bad|
        expect(normalize('4' => { 'brand_new' => bad })).not_to be_valid, "expected #{bad.inspect} to be rejected"
      end
    end

    it 'rejects quantities above the technical bound instead of clamping' do
      expect(normalize('4' => { 'brand_new' => 100_001 })).not_to be_valid
      expect(normalize('4' => { 'brand_new' => '100001' })).not_to be_valid
    end

    it 'rejects ambiguous duplicate products and conditions' do
      expect(normalize('4' => { 'brand_new' => 1 }, 4 => { 'brand_new' => 1 })).not_to be_valid
      expect(normalize('4' => { 'misb' => 1, misb: 1 })).not_to be_valid
    end

    it 'does not partially accept a payload with one bad line' do
      result = normalize('4' => { 'brand_new' => 1 }, '5' => { 'brand_new' => 'x' })
      expect(result).not_to be_valid
      expect(result.lines).to be_empty
      expect(result.payload).to eq({})
      expect(result.digest).to be_nil
    end

    it 'rejects a payload larger than the receipt column allows' do
      huge = (1..600).to_h { |i| [i.to_s, { 'brand_new' => 1 }] }
      expect(normalize(huge)).not_to be_valid
    end
  end
end

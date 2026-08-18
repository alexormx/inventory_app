# frozen_string_literal: true

require 'rails_helper'

# Color, icono, urgencia y auto-cierre salen todos de la misma severidad, así
# que no pueden contradecirse (antes :success caía en el 'else' y se pintaba
# azul de info en vez de verde).
RSpec.describe ApplicationHelper, type: :helper do
  describe '#flash_severity' do
    {
      'notice' => :success, 'success' => :success,
      'alert' => :error, 'error' => :error, 'danger' => :error,
      'warning' => :warning, 'whatever' => :info
    }.each do |key, expected|
      it "maps #{key} to #{expected}" do
        expect(helper.flash_severity(key)).to eq(expected)
      end
    end
  end

  it 'paints a :success flash green, not info blue' do
    expect(helper.bootstrap_class_for(:success)).to eq('alert-success')
  end

  it 'keeps the previous mapping for notice and alert' do
    expect(helper.bootstrap_class_for(:notice)).to eq('alert-success')
    expect(helper.bootstrap_class_for(:alert)).to eq('alert-danger')
  end

  describe 'dismissal policy' do
    it 'never auto-dismisses something the user must act on' do
      expect(helper.flash_auto_dismiss_ms(:error)).to eq(0)
      expect(helper.flash_auto_dismiss_ms(:warning)).to eq(0)
    end

    it 'auto-dismisses purely informational feedback' do
      expect(helper.flash_auto_dismiss_ms(:success)).to be > 0
      expect(helper.flash_auto_dismiss_ms(:info)).to be > 0
    end
  end

  describe 'screen reader urgency' do
    it 'interrupts only for errors and warnings' do
      expect(helper.flash_aria_role(:error)).to eq('alert')
      expect(helper.flash_aria_live(:error)).to eq('assertive')
    end

    it 'announces success politely instead of interrupting' do
      expect(helper.flash_aria_role(:success)).to eq('status')
      expect(helper.flash_aria_live(:success)).to eq('polite')
    end
  end

  describe 'icons' do
    it 'gives each severity a distinct icon' do
      icons = %i[success warning error info].map { |s| helper.flash_icon(s) }
      expect(icons.uniq.size).to eq(4)
    end
  end
end

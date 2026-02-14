# frozen_string_literal: true

class InventoryAdjustment < ApplicationRecord
  # Associations
  has_many :inventory_adjustment_lines, dependent: :destroy
  has_many :inventory_adjustment_entries, through: :inventory_adjustment_lines
  belongs_to :user, optional: true
  belongs_to :applied_by, class_name: 'User', optional: true
  belongs_to :reversed_by, class_name: 'User', optional: true

  # States: only draft/applied
  enum :status, { draft: 'draft', applied: 'applied' }, prefix: true

  # Types (kept as before to preserve UI filters)
  enum :adjustment_type, {
    audit: 'audit',
    correction: 'correction',
    damage: 'damage',
    loss: 'loss',
    found: 'found',
    theft: 'theft',
    rtv: 'rtv',
    other: 'other'
  }

  validates :status, presence: true
  validates :adjustment_type, presence: true
  validate :reference_format_on_apply
  validate :prevent_modification_when_applied

  accepts_nested_attributes_for :inventory_adjustment_lines, allow_destroy: true

  # Generate reference only when applying if missing
  def generate_reference_if_needed!(now = Time.current)
    return if reference.present?

    pattern = begin
      SystemVariable.get('INVENTORY_ADJ_REFERENCE_PATTERN', 'ADJ-YYYYMM')
    rescue StandardError
      'ADJ-YYYYMM'
    end
    resolved_prefix = pattern.gsub('YYYYMM', now.strftime('%Y%m'))
    prefix = resolved_prefix
    # Buscar el último consecutivo existente para el mes (formato ADJ-YYYYMM-NN)
    # Lock rows to prevent concurrent duplicate references
    last = self.class.lock('FOR UPDATE').where('reference LIKE ?', "#{prefix}-%").where.not(reference: nil)
               .order(Arel.sql('reference DESC')).limit(1).pick(:reference)
    seq = if last
            last.split('-').last.to_i + 1
          else
            1
          end
    self.reference = format('%s-%02d', prefix, seq)
  end

  # Apply if draft; no-op if already applied (idempotent)
  def apply!(applied_by: nil, now: Time.current)
    return 0 if status_applied?

    ApplyInventoryAdjustmentService.new(self, applied_by: applied_by, now: now).call
  end

  # Reverse if applied: undo inventory and set back to draft; no-op if already draft
  def reverse!(reversed_by: nil, now: Time.current)
    return 0 if status_draft?

    ReverseInventoryAdjustmentService.new(self, reversed_by: reversed_by, now: now).call
  end

  # Alias for convenience/API symmetry
  def reverse(**)
    reverse!(**)
  end

  private

  def reference_format_on_apply
    return unless status == 'applied'
    return if reference.blank? || reference =~ /\AADJ-\d{6}-\d{2,}\z/

    errors.add(:reference, 'must follow ADJ-YYYYMM-NN (e.g. ADJ-202509-01) or be blank before apply')
  end

  def prevent_modification_when_applied
    return unless status_applied?

    # Permitir sólo los cambios asociados a la transición draft -> applied
    if will_save_change_to_status? && status_change_to_be_saved == %w[draft applied]
      allowed = %w[status applied_at applied_by_id reference updated_at]
      return if (changed - allowed).empty?
    end
    # Permitir reverse (applied -> draft) gestionado por servicio (reversed_at / reversed_by_id)
    if will_save_change_to_status? && status_change_to_be_saved == %w[applied draft]
      allowed = %w[status reversed_at reversed_by_id updated_at]
      return if (changed - allowed).empty?
    end
    # Cualquier otra modificación estando aplicado se bloquea
    return unless changed?

    errors.add(:base, 'Cannot modify an applied adjustment. Reverse it first.')
    
  end
end


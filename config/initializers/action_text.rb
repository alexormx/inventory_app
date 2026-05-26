# frozen_string_literal: true

# Extend Action Text's allowed tags so authors can paste HTML tables
# directly (the default sanitizer drops table-related tags).
#
# IMPORTANT: ActionText::ContentHelper.allowed_tags is nil at boot — it's
# lazily memoized on first render to "Rails sanitizer defaults + figure +
# action-text-attachment". Reading it here would return nil and our union
# would discard ~70 default tags (p, strong, em, ul, ol, li, h1-h6, a,
# img, blockquote, code, pre, etc.), breaking every post on the site.
#
# Instead, we explicitly compose the full list from the sanitizer's own
# defaults + Action Text's framework tags + our table extras.
Rails.application.config.to_prepare do
  sanitizer_class =
    if defined?(Rails::HTML5::SafeListSanitizer)
      Rails::HTML5::SafeListSanitizer
    else
      Rails::HTML::SafeListSanitizer
    end

  base_tags  = sanitizer_class.allowed_tags.to_a
  base_attrs = sanitizer_class.allowed_attributes.to_a

  action_text_tags  = %w[figure action-text-attachment]
  extra_table_tags  = %w[table thead tbody tfoot tr th td caption colgroup col]
  extra_table_attrs = %w[colspan rowspan scope]

  ActionText::ContentHelper.allowed_tags = (base_tags + action_text_tags + extra_table_tags).uniq
  ActionText::ContentHelper.allowed_attributes = (base_attrs + extra_table_attrs).uniq
end

# frozen_string_literal: true

# Action Text's default sanitizer drops table-related tags, which destroyed
# the comparison table the admin pasted on the first blog post (only the
# inner text survived). Extend the allowed tag/attribute lists so authors
# can paste HTML tables directly without losing them.
Rails.application.config.to_prepare do
  extra_tags = %w[table thead tbody tfoot tr th td caption colgroup col]
  extra_attrs = %w[colspan rowspan scope]

  ActionText::ContentHelper.allowed_tags =
    (ActionText::ContentHelper.allowed_tags || []).to_a.union(extra_tags)
  ActionText::ContentHelper.allowed_attributes =
    (ActionText::ContentHelper.allowed_attributes || []).to_a.union(extra_attrs)
end

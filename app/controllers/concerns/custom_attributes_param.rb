module CustomAttributesParam
  extend ActiveSupport::Concern

  private

  # Mutates the given params hash: ensures product[:custom_attributes] is a Hash
  def coerce_custom_attributes!(p)
    v = p[:custom_attributes]
    return p unless v.is_a?(String)

    s = v.strip
    if s.empty?
      p[:custom_attributes] = {}
      return p
    end

    # Try standard JSON
    begin
      p[:custom_attributes] = JSON.parse(s)
      return p
    rescue JSON::ParserError
    end

    # Try Ruby-hash-like => to JSON :
    begin
      s2 = s.gsub('=>', ':')
      p[:custom_attributes] = JSON.parse(s2)
      return p
    rescue JSON::ParserError
    end

    # Last resort: preserve raw
    p[:custom_attributes] = { "raw" => s }
    p
  end
end
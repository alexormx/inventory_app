# Register custom MIME types for use in respond_to blocks.

# XLSX (Excel Open XML)
unless Mime::Type.lookup_by_extension(:xlsx)
  Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx
end

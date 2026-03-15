# frozen_string_literal: true

# Seed default category attribute templates

DIECAST_SCHEMA = [
  { key: "color",                  label: "Color",                  type: "string",  required: true,  position: 1, example: "Azul metálico" },
  { key: "linea",                  label: "Línea",                  type: "string",  required: true,  position: 2, example: "Tomica (Serie regular)" },
  { key: "marca",                  label: "Marca",                  type: "string",  required: true,  position: 3, example: "Takara Tomy" },
  { key: "escala",                 label: "Escala",                 type: "string",  required: true,  position: 4, example: "1:64" },
  { key: "modelo",                 label: "Modelo",                 type: "string",  required: true,  position: 5, example: "Toyota Hilux (No.67)" },
  { key: "origen",                 label: "Origen",                 type: "string",  required: false, position: 6, example: "Japón" },
  { key: "apertura",               label: "Apertura",               type: "boolean", required: false, position: 7, example: "false" },
  { key: "material",               label: "Material",               type: "string",  required: true,  position: 8, example: "Die-cast metálico con piezas plásticas" },
  { key: "suspension",             label: "Suspensión",             type: "boolean", required: false, position: 9, example: "true" },
  { key: "edad_recomendada",       label: "Edad Recomendada",       type: "string",  required: false, position: 10, example: "+3" },
  { key: "fecha_de_lanzamiento",   label: "Fecha de Lanzamiento",   type: "date",    required: false, position: 11, example: "2021-09-18" }
].freeze

CategoryAttributeTemplate.find_or_create_by!(category: "diecast") do |t|
  t.attributes_schema = DIECAST_SCHEMA
  t.active = true
end

puts "  → CategoryAttributeTemplate 'diecast' seeded (#{DIECAST_SCHEMA.size} attributes)"

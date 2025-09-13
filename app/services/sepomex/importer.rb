module Sepomex
	# Importer mínimo placeholder. Completar con lógica real de carga de CPs cuando se disponga.
	# Mantiene compatibilidad con Zeitwerk al definir la constante.
	class Importer
		Result = Struct.new(:rows_processed, :errors, keyword_init: true)

		def initialize(io: nil)
			@io = io # IO opcional (StringIO, File) con datos csv / json
		end

		def call
			# Placeholder: simplemente retorna cero. Extender con parse real.
			Result.new(rows_processed: 0, errors: [])
		end
	end
end


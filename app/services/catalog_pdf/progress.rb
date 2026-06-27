module CatalogPdf
  # Registro de progreso en memoria para la generación del catálogo (admin,
  # solo local). En desarrollo Puma corre un solo proceso, así que un hash
  # protegido por mutex es suficiente para compartir estado entre el hilo que
  # genera el PDF y las peticiones de sondeo (polling) de la UI.
  class Progress
    JOBS = {}
    MUTEX = Mutex.new

    class << self
      def start
        id = SecureRandom.hex(8)
        write(id, status: 'starting', current: 0, total: 0, name: nil)
        id
      end

      def update(id, **attrs)
        MUTEX.synchronize { JOBS[id] = (JOBS[id] || {}).merge(attrs) }
      end

      def fetch(id)
        MUTEX.synchronize { JOBS[id]&.dup }
      end

      def delete(id)
        MUTEX.synchronize { JOBS.delete(id) }
      end

      private

      def write(id, attrs)
        MUTEX.synchronize { JOBS[id] = attrs }
      end
    end
  end
end

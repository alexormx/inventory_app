# frozen_string_literal: true

# El lote de ubicación vivía en la sesión, y la sesión de esta app va en cookie
# (ActionDispatch::Session::CookieStore, 4 KB). Por eso existía un tope de 40
# líneas: no era una regla de negocio, era la cookie. Al pasarlo a la base:
#
#  - deja de haber un límite artificial de productos distintos
#  - el borrador sobrevive a reinicios del dyno y sirve con varios dynos
#  - se puede bloquear una fila para validar "no pasarse del inventario" sin
#    carreras entre dos clics seguidos o dos pestañas
#  - confirmar puede consumir el borrador dentro de la misma transacción, que es
#    lo que hace que un doble envío no asigne dos veces
class CreateLocationAssignmentDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :location_assignment_drafts do |t|
      # Un borrador por administrador: el operador está parado frente a UN
      # estante, y si abre otra pestaña tiene que ver el mismo lote.
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :inventory_location, null: true, foreign_key: true
      # Para distinguir "el lote está vacío porque no has agregado nada" de
      # "está vacío porque lo acabas de asignar": tras un doble clic el segundo
      # envío merece un mensaje que explique qué pasó, no uno que parezca error.
      t.datetime :last_assigned_at
      # El borrador es contexto de trabajo, no una reserva de inventario. Si se
      # abandona, su contenido se limpia al siguiente acceso del administrador
      # para que cantidades viejas no sobrevivan indefinidamente.
      t.datetime :expires_at, null: false
      t.timestamps
    end

    create_table :location_assignment_draft_lines do |t|
      t.references :location_assignment_draft, null: false, foreign_key: true,
                                               index: { name: 'index_la_draft_lines_on_draft' }
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 0
      t.timestamps
    end

    # Agregar el mismo modelo dos veces suma sobre la línea que ya existe; el
    # índice impide que una carrera cree dos filas para el mismo producto.
    add_index :location_assignment_draft_lines,
              %i[location_assignment_draft_id product_id],
              unique: true, name: 'index_la_draft_lines_on_draft_and_product'
    add_index :location_assignment_drafts, :expires_at
  end
end

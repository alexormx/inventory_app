# frozen_string_literal: true

module Users
  # Igual que el de Devise salvo "Eliminar mi cuenta": un cliente con pedidos
  # no se puede borrar (restrict_with_error), así que se anonimiza.
  class RegistrationsController < Devise::RegistrationsController
    # Marca las cuentas creadas por el propio cliente (no por admin ni API)
    # para poder dar seguimiento a las que no confirman su correo.
    def build_resource(hash = {})
      super
      resource.self_registered = true if resource.new_record?
    end

    def destroy
      Users::AnonymizeAccount.call(resource)
      Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
      set_flash_message! :notice, :destroyed
      respond_with_navigational(resource) do
        redirect_to after_sign_out_path_for(resource_name), status: Devise.responder.redirect_status
      end
    rescue Users::AnonymizeAccount::NotAllowed => e
      redirect_to edit_user_registration_path, alert: e.message
    end
  end
end

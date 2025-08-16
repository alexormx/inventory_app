module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  private

  def authenticate_with_token!
    token = request.headers["Authorization"].to_s.split(" ").last
    user = User.find_by(api_token: token)

    if user&.admin?
      @current_user = user
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end

# frozen_string_literal: true

module ShoppingCarts
  # Resolves the authenticated user's single ACTIVE ShoppingCart.
  #
  # The partial unique index index_shopping_carts_on_user_id_when_active is
  # the final authority: two concurrent first-cart creations both INSERT, the
  # loser blocks until the winner commits, then fails with RecordNotUnique and
  # deterministically re-fetches the winner. The INSERT runs in a savepoint so
  # a caller's surrounding transaction survives the losing INSERT.
  class ActiveCartResolver
    def self.find(user)
      user.shopping_carts.find_by(status: 'active')
    end

    def self.find_or_create!(user)
      find(user) || create!(user)
    end

    def self.create!(user)
      ActiveRecord::Base.transaction(requires_new: true) do
        user.shopping_carts.create!(status: 'active', last_activity_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      # The winner has committed; if it somehow rolled back instead, the
      # caller's retry loop will take another turn.
      find(user) || raise
    end
  end
end

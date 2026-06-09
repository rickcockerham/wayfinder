class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  scope :for_user, ->(user) {
    user_id = user.respond_to?(:id) ? user.id : user
    user_id.present? && column_names.include?("user_id") ? where(user_id: user_id) : none
  }

  private

  def associated_user_matches?(association_name)
    record = public_send(association_name)
    return true if record.blank? || user_id.blank? || !record.respond_to?(:user_id)

    record.user_id == user_id
  end

  def validate_associated_user(association_name)
    return if associated_user_matches?(association_name)

    errors.add(association_name, "must belong to the same user")
  end
end

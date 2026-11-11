require 'redmine/twofa/base'

module OutOfBandAuth
  class Email < Redmine::Twofa::Base
    def send_code(controller: nil, action: nil)
      !!AuthSourceOutOfBand.issue!(@user)
    end

    def verify_otp!(code)
      AuthSourceOutOfBand.verify!(@user, code)
    end

    def destroy_pairing_without_verify!
      AuthSourceOutOfBand.where(user_id: @user.id).delete_all
      super
    end

    def otp_confirm_view_variables
      super.merge(resendable: true)
    end
  end
end

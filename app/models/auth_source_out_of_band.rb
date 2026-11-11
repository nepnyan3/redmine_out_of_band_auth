require 'openssl'
require 'securerandom'

class AuthSourceOutOfBand < ApplicationRecord
  CODE_LIFETIME = 2.minutes
  RESEND_INTERVAL = 30.seconds
  MAX_ATTEMPTS = 3

  belongs_to :user

  def self.issue!(user)
    challenge = create_or_find_by!(user_id: user.id)
    challenge.with_lock do
      now = Time.current
      # Resends cannot reset the attempt budget or flood the recipient.
      if challenge.expires_at && challenge.expires_at > now
        return if challenge.attempts >= MAX_ATTEMPTS
        return if challenge.sent_at && challenge.sent_at > now - RESEND_INTERVAL
      end
      code = format('%06d', SecureRandom.random_number(1_000_000))
      attempts = challenge.expires_at && challenge.expires_at > now ? challenge.attempts : 0
      challenge.update!(code_digest: digest(user.id, code), expires_at: now + CODE_LIFETIME,
                        sent_at: now, attempts: attempts)
      # A delivery failure rolls back the challenge. No plaintext code is stored.
      OutOfBandAuthMailer.verification_code(user, code).deliver_now
    end
  end

  def self.verify!(user, code)
    challenge = find_by(user_id: user.id)
    return false unless challenge

    challenge.with_lock do
      return false unless challenge.code_digest.present? && challenge.expires_at > Time.current
      return false if challenge.attempts >= MAX_ATTEMPTS

      challenge.increment!(:attempts)
      valid = code.to_s.match?(/\A[0-9]{6}\z/) &&
              ActiveSupport::SecurityUtils.secure_compare(challenge.code_digest, digest(user.id, code))
      # Consume under the row lock: a successful code cannot be replayed.
      challenge.update!(code_digest: nil) if valid
      valid
    end
  end

  def self.digest(user_id, code)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base,
                           "redmine-oob:#{user_id}:#{code}")
  end
  private_class_method :digest
end

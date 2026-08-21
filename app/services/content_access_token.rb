class ContentAccessToken
  EXPIRY = 1.hour

  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base, digest: "SHA256")
  end

  def self.generate(artifact:, user:)
    verifier.generate(
      { artifact_id: artifact.id, user_id: user.id, slug: artifact.slug, expires_at: EXPIRY.from_now.to_i },
      purpose: :content_access
    )
  end

  # Returns the decoded payload hash if the token is valid, unexpired, and
  # names this exact slug — nil for any other reason (missing, tampered,
  # expired, or minted for a different artifact). Callers should treat nil
  # identically to "no token at all", never as a distinct error.
  def self.verify(token, slug:)
    return nil if token.blank?

    payload = verifier.verify(token, purpose: :content_access)
    return nil unless payload.is_a?(Hash) && payload["expires_at"].is_a?(Integer)
    return nil if payload["expires_at"] < Time.current.to_i
    return nil if payload["slug"] != slug

    payload.symbolize_keys
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end

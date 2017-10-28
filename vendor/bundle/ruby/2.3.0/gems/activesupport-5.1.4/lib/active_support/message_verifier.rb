require "base64"
require "active_support/core_ext/object/blank"
require "active_support/security_utils"

module ActiveSupport
  # +MessageVerifier+ makes it easy to generate and verify messages which are
  # signed to prevent tampering.
  #
  # This is useful for cases like remember-me tokens and auto-unsubscribe links
  # where the session store isn't suitable or available.
  #
  # Remember Me:
  #   cookies[:remember_me] = @verifier.generate([@user.id, 2.weeks.from_now])
  #
  # In the authentication filter:
  #
  #   id, time = @verifier.verify(cookies[:remember_me])
  #   if Time.now < time
  #     self.current_user = User.find(id)
  #   end
  #
  # By default it uses Marshal to serialize the message. If you want to use
  # another serialization method, you can set the serializer in the options
  # hash upon initialization:
  #
  #   @verifier = ActiveSupport::MessageVerifier.new('s3Krit', serializer: YAML)
  #
  # +MessageVerifier+ creates HMAC signatures using SHA1 hash algorithm by default.
  # If you want to use a different hash algorithm, you can change it by providing
  # `:digest` key as an option while initializing the verifier:
  #
  #   @verifier = ActiveSupport::MessageVerifier.new('s3Krit', digest: 'SHA256')
  class MessageVerifier
    class InvalidSignature < StandardError; end

    def initialize(secret, options = {})
      raise ArgumentError, "Secret should not be nil." unless secret
      @secret = secret
      @digest = options[:digest] || "SHA1"
      @serializer = options[:serializer] || Marshal
    end

    # Checks if a signed message could have been generated by signing an object
    # with the +MessageVerifier+'s secret.
    #
    #   verifier = ActiveSupport::MessageVerifier.new 's3Krit'
    #   signed_message = verifier.generate 'a private message'
    #   verifier.valid_message?(signed_message) # => true
    #
    #   tampered_message = signed_message.chop # editing the message invalidates the signature
    #   verifier.valid_message?(tampered_message) # => false
    def valid_message?(signed_message)
      return if signed_message.nil? || !signed_message.valid_encoding? || signed_message.blank?

      data, digest = signed_message.split("--".freeze)
      data.present? && digest.present? && ActiveSupport::SecurityUtils.secure_compare(digest, generate_digest(data))
    end

    # Decodes the signed message using the +MessageVerifier+'s secret.
    #
    #   verifier = ActiveSupport::MessageVerifier.new 's3Krit'
    #
    #   signed_message = verifier.generate 'a private message'
    #   verifier.verified(signed_message) # => 'a private message'
    #
    # Returns +nil+ if the message was not signed with the same secret.
    #
    #   other_verifier = ActiveSupport::MessageVerifier.new 'd1ff3r3nt-s3Krit'
    #   other_verifier.verified(signed_message) # => nil
    #
    # Returns +nil+ if the message is not Base64-encoded.
    #
    #   invalid_message = "f--46a0120593880c733a53b6dad75b42ddc1c8996d"
    #   verifier.verified(invalid_message) # => nil
    #
    # Raises any error raised while decoding the signed message.
    #
    #   incompatible_message = "test--dad7b06c94abba8d46a15fafaef56c327665d5ff"
    #   verifier.verified(incompatible_message) # => TypeError: incompatible marshal file format
    def verified(signed_message)
      if valid_message?(signed_message)
        begin
          data = signed_message.split("--".freeze)[0]
          @serializer.load(decode(data))
        rescue ArgumentError => argument_error
          return if argument_error.message.include?("invalid base64")
          raise
        end
      end
    end

    # Decodes the signed message using the +MessageVerifier+'s secret.
    #
    #   verifier = ActiveSupport::MessageVerifier.new 's3Krit'
    #   signed_message = verifier.generate 'a private message'
    #
    #   verifier.verify(signed_message) # => 'a private message'
    #
    # Raises +InvalidSignature+ if the message was not signed with the same
    # secret or was not Base64-encoded.
    #
    #   other_verifier = ActiveSupport::MessageVerifier.new 'd1ff3r3nt-s3Krit'
    #   other_verifier.verify(signed_message) # => ActiveSupport::MessageVerifier::InvalidSignature
    def verify(signed_message)
      verified(signed_message) || raise(InvalidSignature)
    end

    # Generates a signed message for the provided value.
    #
    # The message is signed with the +MessageVerifier+'s secret. Without knowing
    # the secret, the original value cannot be extracted from the message.
    #
    #   verifier = ActiveSupport::MessageVerifier.new 's3Krit'
    #   verifier.generate 'a private message' # => "BAhJIhRwcml2YXRlLW1lc3NhZ2UGOgZFVA==--e2d724331ebdee96a10fb99b089508d1c72bd772"
    def generate(value)
      data = encode(@serializer.dump(value))
      "#{data}--#{generate_digest(data)}"
    end

    private
      def encode(data)
        ::Base64.strict_encode64(data)
      end

      def decode(data)
        ::Base64.strict_decode64(data)
      end

      def generate_digest(data)
        require "openssl" unless defined?(OpenSSL)
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest.const_get(@digest).new, @secret, data)
      end
  end
end

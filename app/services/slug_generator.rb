class SlugGenerator
  ALPHABET = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
  LENGTH = 8
  MAX_ATTEMPTS = 5

  def self.generate_unique
    MAX_ATTEMPTS.times do
      slug = candidate
      return slug unless Artifact.exists?(slug: slug)
    end

    raise "Unable to generate a unique slug after #{MAX_ATTEMPTS} attempts"
  end

  def self.candidate
    Array.new(LENGTH) { ALPHABET.sample }.join
  end
end

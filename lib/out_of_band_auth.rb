module OutOfBandAuth
  def self.prepare
    # Register each prepare cycle so the scheme follows Rails class reloading.
    Redmine::Twofa.register_scheme('email', Email)
  end
end

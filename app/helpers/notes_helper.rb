# app/helpers/notes_helper.rb
module NotesHelper
  ALLOWED_TAGS = %w[h2 h3 h4 p br b strong i em u a ul ol li pre code blockquote].freeze
  ALLOWED_ATTRS = %w[href title target rel].freeze

  def safe_notes(html)
    sanitize(html.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRS)
  end
end

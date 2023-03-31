require "friendly_id"
require "friendly_id/mobility/version"
require "friendly_id/slug_decorator"

module FriendlyId
  module Mobility
    class << self
      def setup(model_class)
        model_class.friendly_id_config.use :slugged
        if model_class.friendly_id_config.uses? :history
          model_class.instance_eval do
            friendly_id_config.finder_methods = FriendlyId::Mobility::FinderMethods
          end
        end
        if model_class.friendly_id_config.uses? :finders
          warn "[FriendlyId] The Mobility add-on is not compatible with the Finders add-on. " \
            "Please remove one or the other from the #{model_class} model."
        end
      end

      def included(model_class)
        advise_against_untranslated_model(model_class)

        mod = Module.new do
          def friendly
            super.extending(::Mobility::Plugins::ActiveRecord::Query::QueryExtension)
          end
        end
        model_class.send :extend, mod
      end

      def advise_against_untranslated_model(model)
        field = model.friendly_id_config.query_field
        if model.included_modules.grep(::Mobility::Translations).empty? || model.mobility_attributes.exclude?(field.to_s)
          raise "[FriendlyId] You need to translate the '#{field}' field with " \
            "Mobility (add 'translates :#{field}' in your model '#{model.name}')"
        end
      end
      private :advise_against_untranslated_model
    end

    def set_friendly_id(text, locale = nil)
      ::Mobility.with_locale(locale || ::Mobility.locale) do
        super_set_slug normalize_friendly_id(text)
      end
    end

    def should_generate_new_friendly_id?
      send(friendly_id_config.slug_column, locale: ::Mobility.locale).nil?
    end

    def set_slug(normalized_slug = nil)
      (self.translations.map(&:locale).presence || [::Mobility.locale]).each do |locale|
        ::Mobility.with_locale(locale) { super_set_slug(normalized_slug) }
      end
    end

    def super_set_slug(normalized_slug = nil)
      if should_generate_new_friendly_id?
        candidates = FriendlyId::Candidates.new(self, normalized_slug || send(friendly_id_config.base))
        slug = slug_generator.generate(candidates) || resolve_friendly_id_conflict(candidates)
        translation.send("#{friendly_id_config.slug_column}=", slug)
      end
    end

    def translation
      translation_for(::Mobility.locale)
    end

    module FinderMethods
      include ::FriendlyId::History::FinderMethods

      def exists_by_friendly_id?(id)
        where(friendly_id_config.query_field => id).exists? ||
          joins(:slugs).where(slug_history_clause(id)).exists?
      end
    end
  end
end

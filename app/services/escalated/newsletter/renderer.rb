# frozen_string_literal: true

require 'cgi'
require 'base64'

module Escalated
  module Newsletter
    # Renders a NewsletterDelivery to themed HTML.
    #
    # Stage 1: Markdown -> canonical HTML (host integrators register a
    #          renderer via Escalated.configuration.newsletter_markdown
    #          callable; defaults to a minimal renderer that strips HTML
    #          and converts basic markdown).
    # Stage 2: Theme wrapping via ERB (`<slug>.html.erb`).
    # Stage 3: Optional click rewriting + tracking pixel.
    class Renderer
      ALLOWED_SCHEMES = %w[http https mailto tel].freeze

      def render(delivery)
        newsletter = delivery.newsletter
        contact = delivery.contact
        body_markdown = newsletter.body_markdown.presence ||
                        newsletter.template&.body_markdown.to_s
        theme_slug = newsletter.theme.presence ||
                     newsletter.template&.theme.presence ||
                     Escalated.configuration.newsletter_default_theme

        html = markdown_to_html(body_markdown)
        html = resolve_merge_fields(html, contact, delivery)

        themed = render_theme(theme_slug, {
                                subject: newsletter.subject,
                                body: html,
                                unsubscribe_url: unsubscribe_url(delivery),
                                view_in_browser_url: view_in_browser_url(delivery),
                                brand: brand
                              })

        return themed unless Escalated.configuration.newsletter_tracking_enabled?

        themed = rewrite_links(themed, delivery)
        inject_pixel(themed, delivery)
      end

      def unsubscribe_url(delivery)
        "#{base_url}/escalated/n/u/#{delivery.tracking_token}"
      end

      def view_in_browser_url(delivery)
        "#{base_url}/escalated/n/v/#{delivery.tracking_token}"
      end

      def tracking_pixel_url(delivery)
        "#{base_url}/escalated/n/o/#{delivery.tracking_token}.gif"
      end

      private

      def base_url
        (Escalated.configuration.app_url || 'http://localhost').sub(%r{/+$}, '')
      end

      def brand
        {
          name: Escalated.configuration.app_name || 'Support',
          accent: Escalated.configuration.newsletter_brand_accent || '#2563eb',
          logo_url: Escalated.configuration.newsletter_brand_logo_url,
          physical_address: Escalated.configuration.newsletter_brand_physical_address
        }
      end

      def markdown_to_html(markdown)
        renderer = Escalated.configuration.newsletter_markdown_renderer
        return renderer.call(markdown) if renderer.respond_to?(:call)

        # Minimal fallback: HTML-escape and wrap paragraphs. Host integrators
        # should register a real renderer (CommonMarker, Redcarpet, etc.) via
        # Escalated.configuration.newsletter_markdown_renderer = ->(md) { ... }.
        escaped = CGI.escapeHTML(markdown.to_s)
        "<p>#{escaped.split(/\n{2,}/).join('</p><p>')}</p>"
      end

      def resolve_merge_fields(html, contact, delivery)
        html.gsub(/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/) do |_match|
          path = Regexp.last_match(1).strip
          CGI.escapeHTML(resolve_path(path, contact, delivery))
        end
      end

      def resolve_path(path, contact, delivery)
        case path
        when 'contact.name' then contact.name.to_s
        when 'contact.first_name' then contact.name.to_s.split.first.to_s
        when 'contact.email' then contact.email.to_s
        when 'unsubscribe_url' then unsubscribe_url(delivery)
        when 'view_in_browser_url' then view_in_browser_url(delivery)
        else
          if path.start_with?('contact.metadata.')
            key = path.sub(/\Acontact\.metadata\./, '')
            (contact.metadata || {})[key].to_s
          else
            ''
          end
        end
      end

      def render_theme(slug, locals)
        path = theme_path(slug)
        template = File.read(path)
        ERB.new(template, trim_mode: '-').result_with_hash(locals)
      end

      def theme_path(slug)
        roots = [
          Escalated.configuration.newsletter_themes_dir,
          File.expand_path('../../../views/escalated/newsletter_themes', __dir__)
        ].compact
        roots.each do |root|
          candidate = File.join(root, "#{slug}.html.erb")
          return candidate if File.exist?(candidate)

          default = File.join(root, 'default.html.erb')
          return default if File.exist?(default)
        end
        raise "No newsletter theme found for slug=#{slug}"
      end

      def rewrite_links(html, delivery)
        unsub_prefix = unsubscribe_url(delivery)
        view_prefix = view_in_browser_url(delivery)
        html.gsub(/(<a\s[^>]*\bhref=)(["'])(.*?)\2/i) do |match|
          attr_prefix = Regexp.last_match(1)
          quote = Regexp.last_match(2)
          href = Regexp.last_match(3)
          next match if href.blank? || href.start_with?('#')

          scheme = (href.split(':', 2).first || '').downcase
          next "#{attr_prefix}#{quote}##{quote}" unless ALLOWED_SCHEMES.include?(scheme)
          next match if %w[mailto tel].include?(scheme)
          next match if href.start_with?(unsub_prefix) || href.start_with?(view_prefix)

          encoded = Base64.urlsafe_encode64(href, padding: false)
          tracked = "#{base_url}/escalated/n/c/#{delivery.tracking_token}?u=#{encoded}"
          "#{attr_prefix}#{quote}#{tracked}#{quote}"
        end
      end

      def inject_pixel(html, delivery)
        pixel = %(<img src="#{CGI.escapeHTML(tracking_pixel_url(delivery))}" width="1" height="1" alt="" />)
        if html.include?('</body>')
          html.sub('</body>', "#{pixel}</body>")
        else
          html + pixel
        end
      end
    end
  end
end

# Injects the McPublish promo banner into artifact HTML at serve time.
#
# The stored artifact is never modified — this runs on the way out of
# ContentController#serve, so the S3 object and the artifact's byte_size
# stay exactly as the publishing agent wrote them.
#
# Artifacts are arbitrary AI-generated HTML and may carry any CSS, so every
# declaration below is scoped to #mcpublish-banner and marked !important:
# an ID selector plus !important outranks essentially anything an artifact
# declares. A deliberately hostile artifact can still hide the banner with
# its own !important rule; defending against that needs shadow DOM or an
# iframe wrapper, which costs more than it is worth for a promo banner.
#
# The body tag is found by regex rather than by parsing: parsing and
# reserializing arbitrary AI-generated HTML would risk mangling the
# artifact itself, which is a worse failure than a misplaced banner. A
# <body> appearing inside a <script> string or an HTML comment is skipped
# (see unsafe_context?), so the real body tag still wins. Remaining known
# gaps, all rare and non-destructive: a <body> inside a <template> renders
# the banner inert, and an artifact whose own fixed header sits at the top
# of the viewport will be overlapped by the banner.
class ArtifactBanner
  # (?=[\s>]) rather than \b: \b matches the word/hyphen boundary in
  # <body-scroll-lock>, and custom elements are required to contain a
  # hyphen, so \b would match a Web Component before the real body tag.
  BODY_TAG = /<body(?=[\s>])[^>]*>/i
  DOCTYPE = /\A\s*<!doctype[^>]*>/i

  # position:fixed rather than sticky: sticky silently fails inside artifacts
  # that scroll an inner container instead of the body, which is common in
  # AI-generated full-page apps. Fixed always pins, so the html padding-top
  # below reserves the strip the banner would otherwise cover.
  # NOTE: the gsub below collapses newlines, so every line break must fall
  # on a token boundary. Never reflow a rule mid-selector or mid-value: a
  # break at the space in "#mcpublish-banner .mcpb-copy" would silently
  # join it into "#mcpublish-banner.mcpb-copy", a different selector.
  STYLE = <<~'CSS'.gsub(/\s*\n\s*/, "").freeze
    <style id="mcpublish-banner-style">
    html{padding-top:44px !important;scroll-padding-top:44px !important}
    #mcpublish-banner{position:fixed !important;top:0 !important;left:0 !important;right:0 !important;z-index:2147483647 !important;box-sizing:border-box !important;height:44px !important;display:flex !important;align-items:center !important;gap:10px !important;margin:0 !important;padding:0 14px !important;background:#23262e !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Helvetica Neue",Arial,sans-serif !important;font-size:13px !important;line-height:1 !important;text-align:left !important;text-transform:none !important;letter-spacing:normal !important;visibility:visible !important;opacity:1 !important;transform:none !important}
    #mcpublish-banner *{box-sizing:border-box !important;margin:0 !important;padding:0 !important;text-transform:none !important;letter-spacing:normal !important}
    #mcpublish-banner a{text-decoration:none !important}
    #mcpublish-banner .mcpb-brand{display:inline-flex !important;align-items:center !important;gap:7px !important;flex:0 0 auto !important;color:#f7f1e6 !important;font-size:13px !important;font-weight:800 !important}
    #mcpublish-banner svg{display:block !important;width:20px !important;height:20px !important;flex:0 0 auto !important}
    #mcpublish-banner .mcpb-ai{color:#e8643c !important}
    #mcpublish-banner .mcpb-copy{flex:1 1 auto !important;min-width:0 !important;color:#bdb4a2 !important;font-size:12.5px !important;font-weight:400 !important;white-space:nowrap !important;overflow:hidden !important;text-overflow:ellipsis !important}
    #mcpublish-banner .mcpb-copy b{color:#f7f1e6 !important;font-weight:700 !important}
    #mcpublish-banner .mcpb-cta{flex:0 0 auto !important;background:#e8643c !important;color:#ffffff !important;font-size:11.5px !important;font-weight:700 !important;padding:6px 12px !important;border-radius:7px !important}
    @media (max-width:640px){#mcpublish-banner .mcpb-copy{display:none !important}#mcpublish-banner .mcpb-brand{flex:1 1 auto !important}}
    @media print{#mcpublish-banner{display:none !important}html{padding-top:0 !important}}
    </style>
  CSS

  ICON = <<~'SVG'.gsub(/\s*\n\s*/, "").freeze
    <svg viewBox="0 0 110 110" aria-hidden="true">
    <rect width="110" height="110" rx="26" fill="#f7f1e6"/>
    <g transform="translate(55,58)">
    <g fill="#23262e">
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(60)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(120)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(180)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(240)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(300)"/>
    </g>
    <rect x="-6" y="-46" width="12" height="23" rx="6" fill="#e8643c"/>
    </g>
    </svg>
  SVG

  class << self
    def inject(html)
      return html if html.blank?

      markup = STYLE + banner_div
      offset = 0

      while (match = BODY_TAG.match(html, offset))
        unless unsafe_context?(html[0, match.begin(0)])
          return html[0, match.end(0)] + markup + html[match.end(0)..]
        end

        offset = match.end(0)
      end

      if (doctype = DOCTYPE.match(html))
        return doctype[0] + markup + doctype.post_match
      end

      markup + html
    end

    private

    # True when everything before this point leaves an unclosed <script> or
    # <!-- comment open — i.e. a <body> found here is text inside a script
    # literal or a comment, not the document's real body tag. Injecting
    # there would corrupt the script or silently swallow the banner.
    def unsafe_context?(prefix)
      prefix.scan(/<script\b/i).size > prefix.scan(%r{</script\b}i).size ||
        prefix.scan("<!--").size > prefix.scan("-->").size
    end

    # Built per call rather than frozen at load time so the host always
    # reflects the current config (the same reason Artifact#url reads it
    # each call). Only this small div is dynamic; the CSS is a constant.
    def banner_div
      host = "https://#{Rails.application.config.x.main_host}"

      <<~HTML.gsub(/\s*\n\s*/, "")
        <div id="mcpublish-banner">
        <a class="mcpb-brand" href="#{host}" target="_blank" rel="noopener noreferrer">#{ICON}<span>McPublish<span class="mcpb-ai">.ai</span></span></a>
        <span class="mcpb-copy">This page was <b>McPublished</b> straight from an AI chat.</span>
        <a class="mcpb-cta" href="#{host}/signup" target="_blank" rel="noopener noreferrer">McPublish your own &rarr;</a>
        </div>
      HTML
    end
  end
end

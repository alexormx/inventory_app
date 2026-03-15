# frozen_string_literal: true

module Admin
  module ProductEnrichmentHelper
    ENRICHMENT_STATUS_BADGES = {
      "queued"          => { label: "En cola",    css: "bg-secondary" },
      "generating"      => { label: "Generando",  css: "bg-info text-dark" },
      "draft_generated" => { label: "Por revisar", css: "bg-primary" },
      "published"       => { label: "Publicado",  css: "bg-success" },
      "rejected"        => { label: "Rechazado",  css: "bg-danger" },
      "failed"          => { label: "Fallido",    css: "bg-danger" }
    }.freeze

    def render_enrichment_status_badge(status)
      config = ENRICHMENT_STATUS_BADGES[status.to_s] || { label: status, css: "bg-secondary" }
      content_tag(:span, config[:label], class: "badge #{config[:css]}")
    end
  end
end

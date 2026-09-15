# plugin_hooks_example
#
# This file must live at frontend/plugin_init.rb. That's the specific
# path ArchivesSpace looks for it to load it at boot.
#
# Every configured plugin's frontend/plugin_init.rb gets loaded this way,
# one after another. Multiple plugin's plugin_init's won't overwrite or
# replace each other, each just adds their own registrations to a shared
# pool. However, load order does matter and that is determined by the
# order in which plugins are listed in AppConfig[:plugins]. This only
# matters when two plugins register the exact same hook with the exact
# same value (e.g. two plugins both customizing facet labels for
# "created_by"). In those scenarions, which one "wins" depends on the
# specific hook, so check that hook's own behavior rather than assuming.
#
# Everything below is wrapped in Rails.application.config.after_initialize
# because this file loads too early for ArchivesSpace's Plugins module to
# exist yet. Be sure not to remove this wrapper.
Rails.application.config.after_initialize do

  # --- Hook 1: search facets -------------------------------------------------

  Plugins.add_search_facets(:agent_person, "created_by")
  Plugins.add_search_facets(:agent_family, "created_by")
  Plugins.add_search_facets(:agent_corporate_entity, "created_by")
  Plugins.add_search_facets(:agent_software, "created_by")

  Plugins.add_facet_group_i18n("created_by", lambda { |facet_value|
    "plugins.plugin_hooks_example.created_by_facet.admin" if facet_value == "admin"
  })

  # --- Hook 2: Plugins::PluginReadonlySearch ---------------------------------

  Plugins.register_plugin_section(
    Plugins::PluginReadonlySearch.new(
      "plugin_hooks_example",
      "related_by_subject",
      ["resource"],
      :heading_text => "Other Resources Sharing This Resource's First Subject (plugin_hooks_example demo)",
      :filter_term_proc => lambda { |record|
        first_subject_uri = record["subjects"].first && record["subjects"].first["ref"]
        {
          "primary_type" => "resource",
          "subject_uris" => first_subject_uri || "plugin_hooks_example:no-subjects",
        }.to_json
      },
      :only_show_if_results => true
    )
  )

  # --- Hook 3: Named-partial insertion points (`render_plugin_partials`) -----
  # See: `plugin_hooks_example/frontend/views/_*.html.erb`).
  # Those partials are discovered and rendered by filename alone, so nothing
  # needs to be registered here to get them to work.

  # --- Hook 4: Plugins::AbstractPluginSection --------------------------------

  class PluginHooksExampleSection < Plugins::AbstractPluginSection
    def render_readonly(view_context, record, form_context)
      view_context.render_aspace_partial(
        :partial => "plugin_hooks_widgets/abstract_section_readonly",
        :locals => {
          :record => record,
          :section_id => build_section_id(record['jsonmodel_type']),
        }
      )
    end

    def render_edit(view_context, record, form_context)
      view_context.render_aspace_partial(
        :partial => "plugin_hooks_widgets/abstract_section_edit",
        :locals => {
          :form => form_context,
          :section_id => build_section_id(form_context.obj['jsonmodel_type']),
        }
      )
    end
  end

  Plugins.register_plugin_section(
    PluginHooksExampleSection.new(
      "plugin_hooks_example",
      "abstract_section",
      ["resource", "accession"],
      :sidebar_label => "Plugin Hooks Example"
    )
  )

  # --- Hook 5: Plugins.register_note_types_handler ---------------------------

  Plugins.register_note_types_handler(lambda { |jsonmodel_type, note_types, view_context|
    if jsonmodel_type =~ /resource|archival_object/
      note_types["plugin_hooks_example_note"] = {
        :target => :note_multipart,
        :enum => "note_multipart_type",
        :value => "odd",
        :i18n => "Plugin Hooks Example Note (demo -- adds a second General Note entry)",
      }
    end

    note_types
  })

  # --- Hook 6: Plugins.add_resolve_field -------------------------------------

  Plugins.add_resolve_field("classification")

  # --- Hook 7: Plugins.register_edit_role_for_type ---------------------------

  Plugins.register_edit_role_for_type("plugin_hooks_example_widget", "plugin_hooks_example_manage_widgets")

end

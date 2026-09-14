# plugin_hooks_example
#
# See frontend/views/_*.html.erb for the named-partial hooks
# (render_plugin_partials) -- those don't require any registration here,
# just a correctly-named file. See the README for the full list of hooks
# demonstrated and where to find each one.
#
# This file lives at frontend/plugin_init.rb (not the plugin root) because
# that's the exact path frontend/config/application.rb looks for and
# `load`s at boot, once per configured plugin (see its
# "Load plugin init.rb files" block, which calls
# ASUtils.find_local_directories('frontend') then looks for plugin_init.rb
# directly inside each plugin's frontend/ directory). A plugin with a
# backend component would similarly need backend/plugin_init.rb -- that's
# loaded separately by backend/app/main.rb and runs in the backend process,
# not this one. This plugin is frontend-only, so it has no
# backend/plugin_init.rb.
#
# IMPORTANT: frontend/plugin_init.rb is `load`d as a direct side effect of
# frontend/config/application.rb being required by config/environment.rb --
# and that happens BEFORE ArchivesSpace::Application.initialize! runs, which
# is what actually loads config/initializers/*.rb (including
# config/initializers/plugin.rb, the file that defines the `Plugins`
# module/constant). So at the point this file is loaded, `Plugins` does not
# exist yet -- referencing it directly at the top level of this file raises
# `NameError: uninitialized constant Plugins` and prevents the frontend from
# booting at all. Everything below is therefore wrapped in a
# Rails.application.config.after_initialize block, which defers it until
# initializers (and so `Plugins`) are guaranteed to be ready. (application.rb
# itself uses this same hook, just above its plugin-loading loop, to
# force-load JSONModels -- for the same reason.)
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
  # No code here. See: `plugin_hooks_example/frontend/views/_*.html.erb`).
  # Those partials are discovered and rendered by filename alone; nothing needs
  # to be registered here to get them to work.

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

# plugin_hooks_example

An example plugin demonstrating the ways an ArchivesSpace plugin can hook into the
ArchivesSpace staff user interface's (SUI) record forms, listings, and search. This 
plugin functions without touching the underlying schemas, database, or indexer.

Most of what's shown here is grounded in the
["Frontend Specific Hooks"](https://docs.archivesspace.org/customization/plugins/#frontend-specific-hooks)
section of the ArchivesSpace technical documentation: `Plugins.register_plugin_section`
(and its `Plugins::AbstractPluginSection` / `PluginReadonlySearch` building
blocks), `Plugins.add_search_facets` / `add_search_base_facets`,
`Plugins.add_resolve_field`, `Plugins.register_edit_role_for_type`, and
`Plugins.register_note_types_handler`. This plugin also demonstrates a
related but separate mechanism not covered on that page: named-partial
insertion points (`render_plugin_partials`), which core views call at fixed
locations (e.g. the top of a record's Basic Information section, or the
sidebar footer) for any plugin that supplies a matching partial file --
see [Hook 4](#4-named-partial-insertion-points-render_plugin_partials) below
for the mechanics.

This plugin is additive to, not a replacement for, the
[`hello_world`](../hello_world) plugin: `hello_world` demonstrates how to go
further than what's shown here and adds a genuinely new field to the data
model itself. The `hello_world` plugin includes a schema extension, a
database migration, and an indexer hook. The plugin example presented here
is frontend-only and doesn't repeat any of that; it sticks to hooks that
work against the existing schema and data.

## Enabling this plugin

Add `plugin_hooks_example` to `AppConfig[:plugins]` in your `config/config.rb`,
e.g.:

```ruby
AppConfig[:plugins] = ['local', 'lcnaf', 'plugin_hooks_example']
```

then restart ArchivesSpace.

## Before reaching for a plugin

While everything demonstrated here is possible via a plugin, it doesn't mean a
plugin is the right tool for every one of these changes. Some things worth weighing:

- **Plugins are ongoing maintenance, not a one-time change.** A plugin that
  hooks into a view, a helper method, or an internal class (as most of the
  hooks in this example do) is coupled to ArchivesSpace's current
  implementation, not to a stable, versioned public API. Core refactors --
  even ones that aren't meant to be breaking -- can silently change a
  partial's name, a helper's signature, or a class's internals out from
  under a plugin. That risk is concentrated at major upgrades, where a
  plugin that worked fine for several releases can suddenly fail to load, or
  worse, load without error but render incorrectly. Someone has to own
  re-testing (and likely patching) every installed plugin at each upgrade,
  for as long as the plugin stays in use.
- **The ArchivesSpace documentation itself flags this risk generally**: "Be
  sure to test your plugin thoroughly as it may have unanticipated impacts
  on your ArchivesSpace application" ([Plugins
  docs](https://docs.archivesspace.org/customization/plugins/#further-information)).
  The [community webinar "Proactive Change Management for Plugins in
  ArchivesSpace"](https://www.youtube.com/watch?v=GhFA-qxdBXs) goes into
  this in more depth and is worth watching before committing to a plugin
  strategy for a local install.
- **This example plugin is a mockup, not a stress test.** It was written
  and smoke-tested against demo data, on a development install, by hand.
  None of the hooks here have been checked against realistic
  production-scale data volumes, concurrent editing, or repository-specific
  configuration -- e.g. the `PluginReadonlySearch` block in this plugin
  issues a live search API call on every page render, which is a very
  different cost on a repository with a handful of resources versus one
  with hundreds of thousands.
- **Talk to the ArchivesSpace community before writing a plugin from
  scratch.** A given customization may already exist as a shared, maintained
  plugin, or the behavior you want might be a better fit as a core feature
  request. A feature request trades some flexibility on timing and implementation
  for zero ongoing maintenance burden on your end.

## Hooks demonstrated, and where

### 1. Base search facets (`Plugins.add_search_base_facets`)

We can add a facet with a single line: `Plugins.add_search_base_facets("repository")`.

This is the simplest of the facet hooks, but it's also the narrowest in
reach: it only shows up on the general search / "Browse All" results page,
the Advanced Search results page, and the popup search used when linking a
component or accession to another record. Most other places in the staff
interface (a resource's search results, an agent's, etc.) use their own
dedicated facet list instead, so a base facet added here won't appear
there.

We picked `repository` here because it's indexed for every record type
(so it's always populated) and isn't already part of any type's own
default facet list.

### 2. Search facets (`Plugins.add_search_facets` / `add_facet_group_i18n`)

We can add a new facet to a record type's search-results sidebar with a
single line: `Plugins.add_search_facets(:agent_person, "created_by")`. This
plugin does that for all four agent subtypes, adding a "Created By" facet to
the Agents browse/search page.

A couple of things worth knowing about this hook:

- It only controls which *already-indexed* Solr fields get *displayed* as
  facets. It can't add a new indexed field by itself; that would require an
  indexer plugin hook, which is out of scope for this frontend-only demo.
  We picked `created_by` here specifically because it's already indexed for
  every record type.
- The facet group's sidebar heading ("Created By (plugin_hooks_example
  demo)") comes from a locale key we added ourselves, at
  `search.multi.created_by` in this plugin's own
  [`frontend/locales/en.yml`](frontend/locales/en.yml).
- We can also control how individual facet *values* (not just the group
  heading) get displayed, with `Plugins.add_facet_group_i18n`. `created_by`
  values are usernames, one of which we can assume will be `admin`. In this
  example we give just that one value a friendlier label so it stands out from
  ordinary user-created records in the facet list, and leave every other
  username exactly as-is:
  ```ruby
  Plugins.add_facet_group_i18n("created_by", lambda { |facet_value|
    "plugins.plugin_hooks_example.created_by_facet.admin" if facet_value == "admin"
  })
  ```

### 3. `Plugins::PluginReadonlySearch` (embedded "related records" search)

We can also add a new search results/related records search block into an
existing record's read-only/show page without writing any custom search code
ourselves by registering a `Plugins::PluginReadonlySearch`. Just tell it what
to search for (as a filter, built from the record being viewed) and what heading
to use, and it takes care of the rest by reusing ArchivesSpace's own
results-listing partial.

In this plugin, we've registered one for resources that shows other
resources sharing one of the same subjects. This is the same "records linked to
this subject" relationship ArchivesSpace core already shows on a subject's
own page (`subjects/show.html.erb` filters its embedded search on
`"subject_uris" => @subject.uri`); but here we're just approaching it from the
resource side instead, using the resource's first subject as the filter:

```ruby
Plugins::PluginReadonlySearch.new(
  "plugin_hooks_example",
  "related_by_subject",
  ["resource"],
  :heading_text => "...",
  :filter_term_proc => lambda { |record|
    first_subject_uri = record["subjects"].first && record["subjects"].first["ref"]
    {"primary_type" => "resource", "subject_uris" => first_subject_uri || "plugin_hooks_example:no-subjects"}.to_json
  },
  :only_show_if_results => true
)
```

A couple of things worth knowing about this hook:

- We've set `:only_show_if_results => true`, so the section only appears
  when there's actually something to show. This means it does a quick
  search behind the scenes on every page load just to check (see
  `Plugins::PluginReadonlySearch#has_results?`). Definitely something worth
  keeping in mind if this is used on a page that gets a lot of traffic.
- `filter_term_proc` has to return *some* value for every field in its
  filter or else `has_results?` will raise an error. For a resource with no
  subjects at all, we fall back to a filter value that won't match anything
  real (`plugin_hooks_example:no-subjects`), so the section correctly ends up
  hidden for that resource instead of erroring out.
- This demo cuts a couple of real-world corners worth knowing about rather
  than assuming this exact filter is production-ready. It only filters on
  the resource's *first* subject, arbitrarily ignoring any others the
  resource has. It also doesn't exclude the resource being viewed from its own
  results. Neither is a limitation of the hook itself; both choices were made
  to keep this particular example simple.

### 4. Named-partial insertion points (`render_plugin_partials`)

Throughout the SUI, ArchivesSpace's own view code calls out to a
helper, `render_plugin_partials("some_hook_name", ...)`, at specific,
predictable points. We don't have to register anything to use one of these:
we just add a file to our plugin named to match the hook we want, and
ArchivesSpace finds and renders it automatically.

This one mechanism shows up in two different ways. By far the most common
is a matched pair of hook names:
- `top_of_basic_information_<type>` and
- `basic_information_<type>`
repeated across nearly all primary record types' form and show views.

Dropping a file at `frontend/views/_top_of_basic_information_resource.html.erb`
in our plugin, for instance, is all it takes to have that file's content appear
at the top of the Basic Information section on every resource's edit form and show
page; the same naming pattern works for any other record type, just by
swapping `resource` for whatever record type you're modifying in its file name.

Less common, but just as real, are one-off hook names used at a single call
site for something more specific. `sidebar_footer` is used in the shared
sidebar partial, so it applies to every record type's sidebar all at
once. Similarly, `date_fields_ext` is used once inside the shared date
subrecord form, so it applies to every date field across every record type that has
one. This plugin demonstrates one of each kind:

| File in this plugin | Hook name | Appears |
|---|---|---|
| [`frontend/views/_top_of_basic_information_resource.html.erb`](frontend/views/_top_of_basic_information_resource.html.erb) | `top_of_basic_information_resource` | Top of the Basic Information section on a resource's edit form and show page |
| [`frontend/views/_basic_information_resource.html.erb`](frontend/views/_basic_information_resource.html.erb) | `basic_information_resource` | Bottom of the same Basic Information section for resources |
| [`frontend/views/_sidebar_footer.html.erb`](frontend/views/_sidebar_footer.html.erb) | `sidebar_footer` | Bottom of the sidebar on *every* record type's edit/show page |
| [`frontend/views/_date_fields_ext.html.erb`](frontend/views/_date_fields_ext.html.erb) | `date_fields_ext` | Inside every date subrecord form, after certainty/era/calendar |

### 5. `Plugins::AbstractPluginSection` (programmatic sidebar + show + edit section)

When we want to add a whole new section to a record complete with its own
sidebar link, a read-only view, and an editable form, we can subclass 
`Plugins::AbstractPluginSection` and register an instance of it with
`Plugins.register_plugin_section`. From there, ArchivesSpace takes care of calling
our class's `render_sidebar`, `render_readonly`, and `render_edit` methods wherever
they're needed.

This plugin registers one such section (`PluginHooksExampleSection`, in
[`frontend/plugin_init.rb`](frontend/plugin_init.rb)) against both resources
and accessions. It's a minimal example (a more realistic example might be a
computed summary of existing fields or a link out to another system), but it
shows the general shape: a sidebar link, a read-only block, and an edit-mode
block. The two partials it renders are
[`frontend/views/plugin_hooks_widgets/_abstract_section_readonly.html.erb`](frontend/views/plugin_hooks_widgets/_abstract_section_readonly.html.erb)
and
[`frontend/views/plugin_hooks_widgets/_abstract_section_edit.html.erb`](frontend/views/plugin_hooks_widgets/_abstract_section_edit.html.erb).

### 6. `Plugins.register_note_types_handler`

If we want to add a new option to the "Add Note" type dropdown shown on
resource and archival object forms, we can register a small function (a
Ruby proc) that gets a chance to add to -- or otherwise modify -- the list
of available note types every time that dropdown is built:

```ruby
Plugins.register_note_types_handler(lambda { |jsonmodel_type, note_types, view_context|
  # add to or modify note_types here
  note_types
})
```

A genuinely new note *type* (something beyond the stock list of General
Note, Scope and Contents, etc.) needs a matching schema/enum-level change,
which is outside what this frontend-only plugin does (see `hello_world` for
that kind of change). So instead, this plugin's registration just reuses
the stock "General Note" (`"odd"`) value under a different label. While not a
realistic new note kind, this does demonstrate the registration mechanics.

### 7. `Plugins.add_resolve_field`

When ArchivesSpace fetches a record, linked or nested fields normally come
back as bare URI references (e.g. `"/agents/people/1"`) rather than the full
linked object. If we want a field to come back already "resolved" (the
full object instead of just its URI) we can tell ArchivesSpace to always
resolve it with a single call: `Plugins.add_resolve_field("field_name")`.

This plugin calls `Plugins.add_resolve_field("classification")` just to
show the general call shape. In practice, this hook is most useful paired
with a field a plugin has added to the schema itself (see `hello_world` for
how that's done).

It's worth knowing that resolving records isn't free. It's applied globally
to every fetch of any record that has the field, so for a multi-valued field
(one that can have many entries), that's one extra lookup per linked record
on every page load. Only resolve fields you actually need rendered.

There's no visible UI change from this hook on its own. Rather, it's
primarily useful when paired alongside other custom plugin development.

### 8. `Plugins.register_edit_role_for_type`

Search-results listings in the staff interface show an "Edit" button next
to each record (alongside "View"), but only for users who actually have
permission to edit that kind of record. If a plugin introduces a wholly new
record type, ArchivesSpace has no built-in way to know which permission
should control that button for it. That's what this hook is for:
`Plugins.register_edit_role_for_type("my_new_type", "some_permission")`.

To demo this functionality we've simply made up a record type and permission
that don't exist anywhere. Neither value is validated against anything, so we
can do this without any negative effect. But, similarly, since no real search result's
`primary_type` will ever match our made-up one, there's no visible UI change from this hook
on its own here either. Like `add_resolve_field` above, it's primarily
useful alongside other, more involved plugin development particularly those plugins
that introduce new record types of their own.

## What this plugin intentionally does *not* cover

`Plugins::PluginSubRecord`, the `AbstractPluginSection` subclass that builds
on the `config.yml` `parents:` mechanism, isn't demonstrated here either --
it depends on the same real subrecord data that `hello_world` sets up.

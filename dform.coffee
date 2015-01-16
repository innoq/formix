# selectively updates form elements in response to user interaction - typical
# use cases include validation and field dependencies (e.g. multi-step wizards)
#
# this established a pub/sub-like mechanism for form contents: any element can
# subscribe to any field - corresponding changes trigger a form submission, with
# subscribers being updated based on the server response
#
# subscriptions are expressed via a `data-sub` attribute, a space-separated list
# referencing the respective fields' `name` - note that subscribers also require
# an `id` attribute
#
# NB:
# the browser history (i.e. URL) remains untouched, as the server is expected to
# respond with the same resource
#
# Example:
#
#     <form action="/catalog" method="post">
#         <input type="search" name="videogame">
#         ...
#         <label id="platform" class="hidden" data-sub="videogame">
#             <select name="platform" disabled></select>
#         </label>
#     </form>
#
# When something is entered into the `input` field, the form is submitted,
# expecting the server to respond with updated HTML from which the `#platform`
# element is extracted, replacing the existing element of the same ID:
#
#     <label id="platform" class="updated" data-sub="videogame">
#         <select name="platform">
#             <option>Windows</option>
#             <option>PlayStation 3</option>
#             <option>iOS</option>
#         </select>
#     </label>
#
# (note that the `class` and `disabled` attributes have changed or disappeared)
#
# TODO:
# * rather than subscribing to field names directly, use channels (declared via
#   `data-pub` on the respective publisher) for decoupling?
# * support events other than "change" (e.g. "keypress") for more immediate
#   feedback

$ = global.jQuery
util = require("./util")

fieldSelector = "input, select, textarea"

# `selector` references a form
# `options.pending` is an optional class name applied to subscriber elements
# while they are being updated (defaults to "pending")
# `options.before` and `options.after` are optional functions which are invoked
# before the form submission and after the response has been processed - both
# are passed the form, originating field and (to-be-)updated elements
module.exports = (selector, options) ->
	options ||= {}
	dform = new DForm(selector, options.pending, options.before, options.after)
	return dform.form

class DForm
	constructor: (selector, @pending = "pending", @before, @after) ->
		@form = if selector.jquery then selector else $(selector)
		self = @
		@form.on("change", fieldSelector, (ev) ->
			return self.onChange(ev, $(this)))

	subscribers: -> # TODO: allow subscribers from outside the form?
		@_subscribers = @form.find("[data-sub]") unless @_subscribers
		return @_subscribers

	onChange: (ev, field) ->
		name = field.attr("name")
		return unless name

		ids = []
		for node in @subscribers()
			triggers = (trg for trg in $(node).data("sub").split(" ") when trg)
			ids.push(node.id) if name in triggers
			util.error("missing ID", node) unless node.id
		return unless ids.length

		targets = $(document.getElementById(id) for id in ids)
		updates = $()
		@before.call(null, @form, field, targets) if @before
		@submit().
			done((doc) ->
				for target, i in targets
					update = doc.find("##{target.id}")[0]
					return unless update
					$(target).replaceWith(update)
					updates = updates.add(update)
				delete @_subscribers
				return).
			always(=>
				@uncloak(targets) # some might not have been replaced
				@after.call(null, @form, field, updates) if @after
				return)
		@cloak(targets) # NB: disables fields, thus post-serialization

		return

	submit: ->
		res = $.Deferred() # TODO: use proper promises
		req = $.ajax({
			type: @form.attr("method") || "GET"
			url: @form.attr("action")
			data: @form.serialize()
			dataType: "html"
		})
		req.done((html, status, xhr) ->
			nodes = $.parseHTML(html) # excludes scripts
			doc = $("<div />").append(nodes)
			res.resolve(doc)
			return)
		req.fail((xhr, status, err) -> res.reject(err, xhr))

		return res.promise()

	cloak: (els) ->
		for node in els
			el = $(node).addClass(@pending)
			for field in gatherFields(el)
				continue if el.prop("disabled")
				el.prop("disabled", true)
				el.data("dform-disabled", true)
		return

	uncloak: (els) ->
		for node in els
			el = $(node).removeClass(@pending)
			for field in gatherFields(el)
				continue unless el.data("dform-disabled")
				el.prop("disabled", false)
				el.removeData("dform-disabled")
		return

gatherFields = (el) ->
	return if el.is(fieldSelector) then el else return el.find(fieldSelector)

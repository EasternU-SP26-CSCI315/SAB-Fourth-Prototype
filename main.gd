extends Control
class_name TextAdventureMain


@export var start_node: NodePath


## Keys pointing to bools, strings, or numbers
var story_state: Dictionary[String, Variant] = {}

var current_node: StoryNode


@onready var story_text_label: Label = %StoryTextLabel
@onready var choices_box: VBoxContainer = %ChoicesContainer
@onready var nodes_root: Node = %Nodes


func _ready() -> void:
	var start: StoryNode = resolve_story_node_from_path(start_node, self)
	if not is_instance_valid(start):
		push_error("Start node not found. start_node=%s (expected a StoryNode under nodes_root)" % [str(start_node)])
		return

	go_to_node(start)


## Switches the text display to what is defined in the current StoryNode, then rebuilds the list of buttons
func go_to_node(node: StoryNode) -> void:
	current_node = node
	# Could do some tweening here on story_text_label.visible_ratio or visible_characters
	# Could also disable the buttons until the tween is done
	story_text_label.text = current_node.text
	rebuild_choices(current_node.choices)


## Clears old buttons and creates a new button for each of the [Choice]s defined in the current StoryNode
func rebuild_choices(choice_list: Array[Choice]) -> void:
	clear_choices()

	for c in choice_list:
		if not is_instance_valid(c): # This likely won't happen, but just in case...
			continue

		if not choice_is_visible(c): # Check the condition for this choice, move on if not met
			continue

		var b := Button.new()
		choices_box.add_child(b)
		b.text = c.label
		# This could be where some extra formatting options are set.
		# Or, we could create a new scene with just a button inside it, then load that scene in
		#    _ready and instantiate it here, with formatting all set up and ready to go.

		# Connect a lambda function to the button's pressed signal
		# We could absolutely create a function and pass it as a reference below, but this works just as well
		b.pressed.connect(func():
			try_apply_action(c.do)

			var target: StoryNode = resolve_story_node_from_path(c.go_to, current_node)
			# Try a couple more reasonable anchors, since the go_to variable is a relative path
			if target == null:
				target = resolve_story_node_from_path(c.go_to, nodes_root)
			if target == null:
				target = resolve_story_node_from_path(c.go_to, self)

			if target == null:
				push_warning("Choice '%s' go_to (current node: %s) did not resolve: %s" % [c.label, current_node.name, str(c.go_to)])
				return

			go_to_node(target)
		)



#region Condition Checking

## Simple check. If the [Choice] has a condition, then evaluate using [method eval_condition]
func choice_is_visible(c: Choice) -> bool:
	var cond := c.condition.strip_edges()
	if cond == "":
		return true
	return eval_condition(cond)


## Evaluates Conditions [br]
## Format (spaces required): <key> <operator> <value> [br]
## Operators: ==, !=, >=, <=, >, < [br]
func eval_condition(cond: String) -> bool:
	# This is a type-assigmnent quirk in Godot.
	# cond.split returns a PackedStringArray, but I want that to instead be an Array[String]
	# which is a less efficient data type, but is much easier to work on.
	var parts: Array[String]
	parts.assign(cond.split(" ", false))

	# Check that parts makes sense
	if parts.size() < 3:
		push_warning("Bad condition format - exactly three values allowed (expected: <key> <op> <value>): '%s'" % cond)
		# Fails, but still passes
		# I like it this way for debugging/learning purposes, but it's not player-friendly
		return true

	# Parse parts and pass the result to the function that handles comparisons
	var key: String = parts[0]
	var operator: String = parts[1]
	var rhs_str: String = parts[2]

	var lhs: Variant = story_state.get(key, null)

	# The condition is not met if this key does not exist (yet)
	if lhs == null:
		return false

	# At this point, rhs may be either a String, bool, int, or float. Hopefully...
	# lhs was set previously, so it's already the type that we want it to be.
	return compare(lhs, operator, try_parse_value(rhs_str))


## Compares lhs to rhs using the provided operator.
func compare(lhs: Variant, operator: String, rhs: Variant) -> bool:
	var lhs_is_num: bool = (lhs is int) or (lhs is float)
	var rhs_is_num: bool = (rhs is int) or (rhs is float)

	if lhs_is_num and rhs_is_num:
		var a: float = float(lhs)
		var b: float = float(rhs)
		match operator:
			"==": return is_equal_approx(a, b) # Better function to use for floats
			"!=": return a != b
			">=": return a >= b
			"<=": return a <= b
			">":  return a > b
			"<":  return a < b
			_:
				push_warning("Unknown operator '%s' in numeric compare" % operator)
				return false

	# Compare as strings as a default (could be smarter, but it's good enough)
	var sa: String = str(lhs)
	var sb: String = str(rhs)
	match operator:
		"==": return sa == sb
		"!=": return sa != sb
		">=": return sa >= sb
		"<=": return sa <= sb
		">":  return sa > sb
		"<":  return sa < sb
		_:
			push_warning("Unknown operator '%s' in string compare" % operator)
			return false

#endregion


#region Performing Actions

## Apply Actions [br]
## Attempts to evaluate what was provided in Choice.do [br]
## Supports: [br]
##   set <key> <true|false|number|string> [br]
##   inc <key> <amount> [br]
##   dec <key> <amount> [br]
func try_apply_action(cmd: String) -> void:
	cmd = cmd.strip_edges()
	if cmd.is_empty():
		return

	var parts: Array[String]
	parts.assign(cmd.split(" ", false))
	if parts.is_empty():
		return

	if parts.size() != 3:
		push_warning("Bad command: '%s' \nShould have exactly three parts." % cmd)
		return

	var key: String = parts[1]
	match parts[0]:
		"set":
			var value_str: String = parts[2]
			story_state[key] = try_parse_value(value_str)

		"inc":
			var amt: int = int(try_parse_value(parts[2]))
			story_state[key] = int(story_state.get(key, 0)) + amt

		"dec":
			var amt: int = int(try_parse_value(parts[2]))
			story_state[key] = int(story_state.get(key, 0)) - amt

		_:
			push_warning("Unknown action command: '%s'. Only set, inc, and dec are supported." % cmd)

#endregion


#region Utility

## Tries to parse a String into either a: bool, int, or float, with a String as a default if all else fails.
func try_parse_value(s: String):
	s = s.strip_edges()

	# bool
	if s.to_lower() == "true":
		return true
	if s.to_lower() == "false":
		return false

	# numbers
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)

	return s


## NodePath resolution.
## NodePaths are similar in ways to file paths in that they can be relative or absolute.
## The go_to variable in [Choice] is a NodePath relative to the StoryNode that Choice was defined in.
## The question is: relative to what? That's what anchor allows us to check.
func resolve_story_node_from_path(path: NodePath, anchor: Node) -> StoryNode:
	if not is_instance_valid(anchor) or path.is_empty():
		return null

	var n = anchor.get_node_or_null(path)
	if n is StoryNode:
		return n

	# The provided path does not point to a StoryNode relative to anchor.
	return null


## Calls queue_free() on each of the nodes under choices_box.
## queue_free() just tells that node to delete itself at the very end of the current frame.
## Its generally better for performance and good practice to call queue_free() instead of free().
func clear_choices() -> void:
	for child in choices_box.get_children():
		child.queue_free()

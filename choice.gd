extends Resource
class_name Choice
## Resource representing an individual choice


## Required: The text displayed on the button which represents this choice
@export var label: String = ""
## Required: The path to the StoryNode to switch to if the button representing this choice is picked
@export var go_to: NodePath

@export_group("Optional")
## Optional: condition that must be met to show this choice. [br]
## Format (spaces required): <key> <operator> <value> [br]
## Allowed operators: ==, !=, >=, <=, >, < [br]
## Allowing multiple conditions is left as an exercise to the reader!
@export var condition: String = ""
## Optional: actions that happen as a result of this choice being selected. [br]
## Supported: [br]
##    set <key> <true|false|number|string> [br]
##    inc <key> <amount> [br]
##    dec <key> <amount> [br]
## Allowing multiple actions is left as an exercise to the reader!
@export var do: String = ""

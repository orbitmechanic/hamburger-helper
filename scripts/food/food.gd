class_name Food
extends Resource
## Definition of a single food item, its look, and the burger scoring rules.
##
## Definitions live in code rather than as .tres assets so that the whole
## ingredient set is reviewable in a diff and needs no import step.

enum Kind {
	BUN_BOTTOM,
	BUN_TOP,
	LETTUCE,
	TOMATO,
	CHEESE,
	MEAT,
	PICKLE,
	ONION,
}

const DEFS := {
	Kind.BUN_BOTTOM: {
		"name": "Bun",
		"color": Color("d9a05b"),
		"accent": Color("b87a3c"),
		"is_bun": true,
		"bun_role": "bottom",
	},
	Kind.BUN_TOP: {
		"name": "Bun Lid",
		"color": Color("eec27f"),
		"accent": Color("c98f4a"),
		"is_bun": true,
		"bun_role": "top",
	},
	Kind.LETTUCE: {
		"name": "Lettuce",
		"color": Color("6fc24a"),
		"accent": Color("4c9a2c"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.TOMATO: {
		"name": "Tomato",
		"color": Color("e2453c"),
		"accent": Color("b02a24"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.CHEESE: {
		"name": "Cheese",
		"color": Color("f5c53a"),
		"accent": Color("d09c1c"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.MEAT: {
		"name": "Meat",
		"color": Color("7b4a2a"),
		"accent": Color("5a3320"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.PICKLE: {
		"name": "Pickle",
		"color": Color("3f8f3a"),
		"accent": Color("2c6628"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.ONION: {
		"name": "Onion",
		"color": Color("b57edc"),
		"accent": Color("8a5aa8"),
		"is_bun": false,
		"bun_role": "",
	},
}

## Score for a finished burger: 100 for the first ingredient, +50 each after.
const BASE_POINTS := 100
const EXTRA_POINTS := 50


static func def(kind: Kind) -> Dictionary:
	return DEFS[kind]


static func display_name(kind: Kind) -> String:
	return String(DEFS[kind]["name"])


static func is_bun(kind: Kind) -> bool:
	return bool(DEFS[kind]["is_bun"])


static func color_of(kind: Kind) -> Color:
	return DEFS[kind]["color"]


static func accent_of(kind: Kind) -> Color:
	return DEFS[kind]["accent"]


static func burger_points(kinds: Array) -> int:
	var fillings := 0
	for k in kinds:
		if not is_bun(k):
			fillings += 1
	if fillings <= 0:
		return 0
	return BASE_POINTS + (fillings - 1) * EXTRA_POINTS

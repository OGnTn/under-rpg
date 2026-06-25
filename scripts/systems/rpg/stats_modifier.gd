# stat_modifier.gd
class_name StatsModifier
extends Resource

enum Type { FLAT, PERCENT_ADD, PERCENT_MULT }

@export var stat_name: String
@export var value: float
@export var type: Type = Type.FLAT
var source: Object # Useful for debugging (knowing which item caused the buff) (runtime only)

func _init(_name: String = "", _val: float = 0.0, _type: Type = Type.FLAT, _source = null):
	stat_name = _name
	value = _val
	type = _type
	source = _source


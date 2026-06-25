# aura_instance.gd
class_name AuraInstance
extends RefCounted

var aura: Resource
var time_remaining: float
var tick_timer: float
var effect_node: Node = null

func _init(_aura: Resource):
	aura = _aura
	time_remaining = aura.duration
	tick_timer = aura.tick_interval

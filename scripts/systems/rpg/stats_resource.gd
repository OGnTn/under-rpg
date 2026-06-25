# stat_resource.gd
class_name StatsResource
extends Resource

# Using a signal allows the UI to update when values change
signal stat_changed(stat_name, new_value)

# Define your stats here. 
# You can use a Dictionary for flexibility, or hardcoded variables for autocomplete support.
@export_group("Primary Stats")
@export var constitution: int = 10 # Determines max health + stun resistance
@export var defense: int = 10 # Determines damage reduction + knockback resistance
@export var strength: int = 10 # Determines Melee AP + crit chance
@export var agility: int = 10 # Determines Ranged AP + attack speed
@export var intelligence: int = 10 # Determines Magic AP + cooldown reduction
@export var wisdom: int = 10 # Determines mana and health regen + armor penetration

# Helper to access properties dynamically if needed
func get_stat(stat_name: String):
	return get(stat_name)

func set_stat(stat_name: String, value):
	set(stat_name, value)
	stat_changed.emit(stat_name, value)
	
# Create a unique copy of this resource
func duplicate_stats() -> StatsResource:
	var new_stats = self.duplicate(true)
	return new_stats

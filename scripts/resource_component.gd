extends Node
class_name ResourceComponent

signal health_changed(old_value: int, new_value: int)
signal health_depleted()

signal mana_changed(old_value: int, new_value: int)
signal stamina_changed(old_value: int, new_value: int)

@export var max_health: int = 100
@export var current_health: int = 100

@export var max_mana: int = 100
@export var current_mana: int = 100

@export var max_stamina: int = 100
@export var current_stamina: int = 100

@export var destroy_parent_on_depletion: bool = false

# Sibling StatsComponent
var stats_component: Node = null

# Fallback regeneration exports (for entities that do not have a StatsComponent)
@export_group("Fallback Regeneration")
@export var health_regen_per_sec: float = 0.0
@export var mana_regen_per_sec: float = 0.0
@export var stamina_regen_per_sec: float = 0.0

@export_group("UI Settings")
@export var show_health_bar: bool = true
@export var health_bar_offset: float = 2.0
@export var always_show_health_bar: bool = false
@export var health_bar_max_screen_distance_pct: float = 0.25

# Floating-point accumulators to support sub-unit fractional tick regeneration
var _health_accum: float = 0.0
var _mana_accum: float = 0.0
var _stamina_accum: float = 0.0

func _ready():
	current_health = max_health
	current_mana = max_mana
	current_stamina = max_stamina
	
	# Find sibling StatsComponent
	stats_component = get_parent().find_child("StatsComponent", true, false)
	if stats_component:
		stats_component.active_values_changed.connect(_on_stats_changed)
		_on_stats_changed()
	
	# Find sibling Hittable to connect to
	for child in get_parent().get_children():
		if child is Hittable:
			child.hit.connect(_on_hittable_hit)
			
	if show_health_bar:
		call_deferred("_setup_health_bar")

func _process(delta: float) -> void:
	_apply_regeneration(delta)

func _on_stats_changed() -> void:
	if not stats_component:
		return
		
	var old_max_health = max_health
	var old_max_mana = max_mana
	var old_max_stamina = max_stamina
	
	max_health = stats_component.max_health
	max_mana = stats_component.max_mana
	max_stamina = stats_component.max_stamina
	
	# Clamp pools to new maxes if needed
	if current_health > max_health:
		var old = current_health
		current_health = max_health
		health_changed.emit(old, current_health)
		
	if current_mana > max_mana:
		var old = current_mana
		current_mana = max_mana
		mana_changed.emit(old, current_mana)
		
	if current_stamina > max_stamina:
		var old = current_stamina
		current_stamina = max_stamina
		stamina_changed.emit(old, current_stamina)

func _on_hittable_hit(damage: int, damage_source: Node3D, _pos: Vector3, _normal: Vector3):
	if multiplayer.is_server():
		# Check tool compatibility if present
		var tool_compat = get_parent().find_child("ToolCompatibilityComponent", true, false)
		if tool_compat and not tool_compat.is_compatible(damage_source):
			return
		
		take_damage(damage)

func take_damage(amount: int):
	if current_health <= 0:
		return
	var old_health = current_health
	current_health = max(0, current_health - amount)
	health_changed.emit(old_health, current_health)
	
	if current_health <= 0:
		health_depleted.emit()
		if destroy_parent_on_depletion:
			get_parent().queue_free()

func heal(amount: int):
	if current_health <= 0 or amount <= 0:
		return
	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	health_changed.emit(old_health, current_health)

func use_mana(amount: int) -> bool:
	if current_mana < amount:
		return false
	var old_mana = current_mana
	current_mana -= amount
	mana_changed.emit(old_mana, current_mana)
	return true

func restore_mana(amount: int):
	if amount <= 0:
		return
	var old_mana = current_mana
	current_mana = min(max_mana, current_mana + amount)
	mana_changed.emit(old_mana, current_mana)

func use_stamina(amount: int) -> bool:
	if current_stamina < amount:
		return false
	var old_stamina = current_stamina
	current_stamina -= amount
	stamina_changed.emit(old_stamina, current_stamina)
	return true

func restore_stamina(amount: int):
	if amount <= 0:
		return
	var old_stamina = current_stamina
	current_stamina = min(max_stamina, current_stamina + amount)
	stamina_changed.emit(old_stamina, current_stamina)

func _apply_regeneration(delta: float) -> void:
	# Only regenerate if the entity is alive
	if current_health <= 0:
		return
		
	var h_regen = health_regen_per_sec
	var m_regen = mana_regen_per_sec
	var s_regen = stamina_regen_per_sec
	
	if stats_component:
		h_regen = stats_component.health_regen
		m_regen = stats_component.mana_regen
		s_regen = stats_component.stamina_regen
		
	# Health regeneration
	if h_regen > 0.0 and current_health < max_health:
		_health_accum += h_regen * delta
		if _health_accum >= 1.0:
			var amount = int(_health_accum)
			_health_accum -= amount
			heal(amount)
			
	# Mana regeneration
	if m_regen > 0.0 and current_mana < max_mana:
		_mana_accum += m_regen * delta
		if _mana_accum >= 1.0:
			var amount = int(_mana_accum)
			_mana_accum -= amount
			restore_mana(amount)
			
	# Stamina regeneration
	if s_regen > 0.0 and current_stamina < max_stamina:
		_stamina_accum += s_regen * delta
		if _stamina_accum >= 1.0:
			var amount = int(_stamina_accum)
			_stamina_accum -= amount
			restore_stamina(amount)

func _setup_health_bar() -> void:
	if not get_parent():
		return
	# Check if parent already has a ResourceBar3D child
	for child in get_parent().get_children():
		if child.get_script() and child.get_script().get_path() == "res://scripts/resource_bar_3d.gd":
			return
			
	# Instantiate ResourceBar3D
	var bar_script = preload("res://scripts/resource_bar_3d.gd")
	var bar = Sprite3D.new()
	bar.set_script(bar_script)
	bar.vertical_offset = health_bar_offset
	bar.always_show = always_show_health_bar
	bar.max_screen_distance_pct = health_bar_max_screen_distance_pct
	bar.name = "ResourceBar3D"
	get_parent().add_child(bar)

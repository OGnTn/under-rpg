class_name StatsComponent
extends Node

signal modified_stats_changed(stats: StatsResource)
signal active_values_changed # Optional: Useful for UI to update bars/labels

# The "Template" or "Save Data" stats
@export var base_stats: StatsResource

# The "Runtime" stats (read-only for external systems usually)
var modified_stats: StatsResource

# Array to hold active modifiers
var _modifiers: Array = []

# Array to hold active auras
var _active_auras: Array = []

# --- Active Values (Derived Stats) ---
var max_health: int
var health_regen: int

var max_mana: int
var mana_regen: int

var max_stamina: int
var stamina_regen: int

var melee_ap: int
var ranged_ap: int
var magic_ap: int

var damage_reduction: int
var attack_speed: int
var critical_chance: int
var stun_resistance: int
var knockback_resistance: int
var cooldown_reduction: int
var armor_penetration: int

# Cache helper
var _resource_component_cached: Node = null
func _get_resource_component() -> Node:
	if not _resource_component_cached and get_parent():
		_resource_component_cached = get_parent().find_child("ResourceComponent", true, false)
	return _resource_component_cached

# Backwards compatible property getters/setters
var _current_health_fallback: int = 100
var current_health: int:
	get:
		var res = _get_resource_component()
		return res.current_health if res else _current_health_fallback
	set(val):
		var res = _get_resource_component()
		if res:
			res.current_health = val
		else:
			_current_health_fallback = val

var _mana_fallback: int = 100
var mana: int:
	get:
		var res = _get_resource_component()
		return res.current_mana if res else _mana_fallback
	set(val):
		var res = _get_resource_component()
		if res:
			res.current_mana = val
		else:
			_mana_fallback = val

func _ready() -> void:
	# Initialize modified_stats as a unique copy of base_stats
	if base_stats:
		modified_stats = base_stats.duplicate_stats()
	else:
		modified_stats = StatsResource.new()
	
	# Calculate stats for the first time
	recalculate_stats()
	
	# Initialize pools
	var res = _get_resource_component()
	if res:
		res.current_health = max_health
		res.current_mana = max_mana
		res.current_stamina = max_stamina
	else:
		_current_health_fallback = max_health
		_mana_fallback = max_mana

	# Find sibling inventory if present and listen to equipment updates
	var inventory = get_parent().find_child("Inventory", true, false)
	if inventory:
		inventory.equipment_updated.connect(_on_equipment_updated)
		_on_equipment_updated()

func _process(delta: float) -> void:
	_tick_auras(delta)

# Call this when equipping items, applying buffs, or leveling up
func recalculate_stats() -> void:
	if not base_stats: return
	
	# 1. Reset derived to base
	var properties = base_stats.get_property_list()
	for prop in properties:
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var base_val = base_stats.get(prop.name)
			modified_stats.set(prop.name, base_val)

	# 2. Apply Modifiers to the Primary Stats
	for mod in _modifiers:
		var current_val = modified_stats.get(mod.stat_name)
		
		# Skip if the modifier is meant for an Active Value directly (optional safety)
		if current_val == null: continue
		
		match mod.type:
			StatsModifier.Type.FLAT:
				var new_val = current_val + mod.value
				if typeof(current_val) == TYPE_INT:
					new_val = int(round(new_val))
				modified_stats.set(mod.stat_name, new_val)
			StatsModifier.Type.PERCENT_ADD:
				var increase = current_val * (mod.value / 100.0)
				var new_val = current_val + increase
				if typeof(current_val) == TYPE_INT:
					new_val = int(round(new_val))
				modified_stats.set(mod.stat_name, new_val)

	# 3. Recalculate Active Values based on new Primary Stats
	recalculate_active_values()

	modified_stats_changed.emit(modified_stats)

# Converts Primary Stats (Resource) -> Secondary Stats (Component Variables)
func recalculate_active_values() -> void:
	# --- CONSTITUTION ---
	# Formula: 1 Con = 10 HP, 0.5 Stun Res
	max_health = modified_stats.constitution * 10
	stun_resistance = int(modified_stats.constitution * 0.5)
	
	# --- DEFENSE ---
	# Formula: 1 Def = 0.5% Dmg Red, 1 Knockback Res
	damage_reduction = int(modified_stats.defense * 0.5)
	knockback_resistance = modified_stats.defense * 1
	
	# --- STRENGTH ---
	# Formula: 1 Str = 2 Melee AP, 0.2% Crit
	melee_ap = modified_stats.strength * 2
	critical_chance = int(modified_stats.strength * 0.2)
	
	# --- AGILITY ---
	# Formula: 1 Agi = 2 Ranged AP, 0.5 Attack Speed
	ranged_ap = modified_stats.agility * 2
	attack_speed = int(modified_stats.agility * 0.5)
	
	# --- INTELLIGENCE ---
	# Formula: 1 Int = 2 Magic AP, 0.2 Cooldown Red
	magic_ap = modified_stats.intelligence * 2
	cooldown_reduction = int(modified_stats.intelligence * 0.2)
	
	# --- WISDOM ---
	# Formula: 1 Wis = 10 Mana, 1 Armor Pen, Regens
	max_mana = modified_stats.wisdom * 10
	armor_penetration = modified_stats.wisdom * 1
	health_regen = int(modified_stats.wisdom * 0.1)
	mana_regen = int(modified_stats.wisdom * 0.2)

	# --- STAMINA (Derived from agility) ---
	max_stamina = 100 + modified_stats.agility * 2
	stamina_regen = int(5 + modified_stats.agility * 0.1)

	# --- POOL SAFETY CHECKS ---
	var res = _get_resource_component()
	if res:
		# Let ResourceComponent clamp its own pools during recalculation if needed
		# but we can force it here too
		if res.current_health > max_health:
			res.current_health = max_health
		if res.current_mana > max_mana:
			res.current_mana = max_mana
		if res.current_stamina > max_stamina:
			res.current_stamina = max_stamina
	else:
		if _current_health_fallback > max_health:
			_current_health_fallback = max_health
		if _mana_fallback > max_mana:
			_mana_fallback = max_mana
		
	active_values_changed.emit()

func add_modifier(mod: Resource) -> void:
	_modifiers.append(mod)
	recalculate_stats()

func remove_modifier(source: Object) -> void:
	_modifiers = _modifiers.filter(func(m): return m.source != source)
	recalculate_stats()

# --- EQUIPMENT HANDLER ---
func _on_equipment_updated() -> void:
	# Filter out any modifiers whose source is an EquipmentItem
	_modifiers = _modifiers.filter(func(m): return not (m.source is EquipmentItem))
	
	var inventory = get_parent().find_child("Inventory", true, false)
	if inventory:
		for slot in inventory.equipment_container:
			if slot and not slot.is_empty() and slot.item is EquipmentItem:
				var eq_item: EquipmentItem = slot.item
				if "stat_modifiers" in eq_item:
					for mod in eq_item.stat_modifiers:
						var runtime_mod = StatsModifier.new(mod.stat_name, mod.value, mod.type, eq_item)
						_modifiers.append(runtime_mod)
						
	recalculate_stats()

# --- AURA SYSTEM ---
func apply_aura(aura: Resource) -> void:
	# Check if already applied to refresh duration
	for aura_inst in _active_auras:
		if aura_inst.aura.id == aura.id:
			aura_inst.time_remaining = aura.duration
			aura_inst.tick_timer = aura.tick_interval
			return
			
	# Instantiate aura state
	var new_inst = preload("res://scripts/systems/rpg/aura_instance.gd").new(aura)
	_active_auras.append(new_inst)
	
	# Instantiate visual effect if present
	if aura.effect_scene and get_parent() is Node3D:
		var inst = aura.effect_scene.instantiate()
		get_parent().add_child(inst)
		# If the instanced node is Node3D, place it at local origin relative to parent
		if inst is Node3D:
			inst.position = Vector3.ZERO
		new_inst.effect_node = inst
		
	# Apply stat modifiers
	for mod in aura.stat_modifiers:
		var runtime_mod = StatsModifier.new(mod.stat_name, mod.value, mod.type, aura)
		_modifiers.append(runtime_mod)
		
	recalculate_stats()

func remove_aura(aura: Resource) -> void:
	var index = -1
	for i in range(_active_auras.size()):
		if _active_auras[i].aura.id == aura.id:
			index = i
			break
			
	if index != -1:
		var aura_inst = _active_auras[index]
		_active_auras.remove_at(index)
		
		# Clean up visual node
		if aura_inst.effect_node and is_instance_valid(aura_inst.effect_node):
			aura_inst.effect_node.queue_free()
			
		# Filter out modifiers sourced from this aura
		_modifiers = _modifiers.filter(func(m): return m.source != aura)
		
		recalculate_stats()

func has_aura(aura_id: String) -> bool:
	for aura_inst in _active_auras:
		if aura_inst.aura.id == aura_id:
			return true
	return false

func _tick_auras(delta: float) -> void:
	var to_remove: Array[AuraInstance] = []
	
	# We copy array to avoid mutation bugs during iteration
	var current_auras = _active_auras.duplicate()
	for aura_inst in current_auras:
		# Count down duration (if not permanent/infinite)
		if aura_inst.aura.duration > 0.0:
			aura_inst.time_remaining -= delta
			if aura_inst.time_remaining <= 0.0:
				to_remove.append(aura_inst)
				continue
		
		# Count down ticks
		if aura_inst.aura.tick_interval > 0.0:
			aura_inst.tick_timer -= delta
			if aura_inst.tick_timer <= 0.0:
				aura_inst.tick_timer += aura_inst.aura.tick_interval
				_apply_aura_tick(aura_inst.aura)
				
	for aura_inst in to_remove:
		remove_aura(aura_inst.aura)

func _apply_aura_tick(aura: Resource) -> void:
	var res = _get_resource_component()
	if res:
		if aura.damage_per_tick > 0:
			res.take_damage(aura.damage_per_tick)
		if aura.healing_per_tick > 0:
			res.heal(aura.healing_per_tick)
		if aura.mana_per_tick != 0:
			res.restore_mana(aura.mana_per_tick)
		if aura.stamina_per_tick != 0:
			res.restore_stamina(aura.stamina_per_tick)

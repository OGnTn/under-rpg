extends Control
class_name HUDControl

@onready var health_bar: ProgressBar = %PlayerHealthBar
@onready var stamina_bar: ProgressBar = %PlayerStaminaBar
@onready var mana_bar: ProgressBar = %PlayerManaBar

var resource_component: ResourceComponent = null

func _ready() -> void:
	# Find ResourceComponent on the character (owner or grandparent)
	#var character = owner
	#if not character:
	var character = get_parent().get_parent() # HUDControl -> UICanvas -> Character
		
	if character:
		resource_component = character.find_child("ResourceComponent", true, false) as ResourceComponent
		
	if resource_component:
		resource_component.health_changed.connect(_on_health_changed)
		resource_component.mana_changed.connect(_on_mana_changed)
		resource_component.stamina_changed.connect(_on_stamina_changed)
		
		# Initial update
		_update_health(resource_component.current_health, resource_component.max_health)
		_update_mana(resource_component.current_mana, resource_component.max_mana)
		_update_stamina(resource_component.current_stamina, resource_component.max_stamina)
		print("Initiatl resource HUD update sent")
	else:
		push_warning("HUDControl: ResourceComponent not found on parent/owner.")

func _process(delta: float) -> void:
	_update_health(resource_component.current_health, resource_component.max_health)
	_update_mana(resource_component.current_mana, resource_component.max_mana)
	_update_mana(resource_component.current_stamina, resource_component.max_stamina)

func _on_health_changed(_old_val: int, new_val: int) -> void:
	if resource_component:
		_update_health(new_val, resource_component.max_health)

func _on_mana_changed(_old_val: int, new_val: int) -> void:
	if resource_component:
		_update_mana(new_val, resource_component.max_mana)

func _on_stamina_changed(_old_val: int, new_val: int) -> void:
	if resource_component:
		_update_stamina(new_val, resource_component.max_stamina)

func _update_health(current: int, max_val: int) -> void:
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current

func _update_mana(current: int, max_val: int) -> void:
	if mana_bar:
		mana_bar.max_value = max_val
		mana_bar.value = current

func _update_stamina(current: int, max_val: int) -> void:
	if stamina_bar:
		stamina_bar.max_value = max_val
		stamina_bar.value = current

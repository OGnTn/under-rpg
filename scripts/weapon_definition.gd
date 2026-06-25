extends Resource
class_name WeaponDefinition

## Data needed to plug a weapon into the view-model attack system.
## The rest pose and attack pose keys can be authored as one-key animations or
## direct transforms, which keeps weapon-specific animations modular.

@export var weapon_name: StringName = &"sword"
@export var hurtbox_path: NodePath

@export_group("Rest Pose")
@export var rest_animation: StringName = &"r_rest"
@export var rest_position: Vector3 = Vector3(0.6, 1.3, -0.8)
@export var rest_rotation: Vector3 = Vector3.ZERO

@export_group("Draw Pose")
@export var draw_animation: StringName = &""

@export_group("Attacks")
@export var default_attack: StringName = &"regular"
@export var attacks: Array[WeaponAttackDefinition] = []

func get_attack(attack_name: StringName) -> WeaponAttackDefinition:
	for attack in attacks:
		if attack and attack.attack_name == attack_name:
			return attack
	return null

func get_default_attack() -> WeaponAttackDefinition:
	var attack := get_attack(default_attack)
	if attack:
		return attack
	return attacks[0] if not attacks.is_empty() else null

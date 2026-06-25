# aura.gd
class_name Aura
extends Resource

@export_group("Identification")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Duration & Ticking")
## The total duration of the aura in seconds. Use 0 or less for infinite/permanent duration.
@export var duration: float = 0.0
## Interval between ticks in seconds. Use 0 or less for no periodic ticks.
@export var tick_interval: float = 0.0

@export_group("Modifiers")
## The stat modifiers applied to the entity while this aura is active.
@export var stat_modifiers: Array[Resource] = []

@export_group("Periodic Tick Effects")
@export var damage_per_tick: int = 0
@export var healing_per_tick: int = 0
@export var mana_per_tick: int = 0
@export var stamina_per_tick: int = 0

@export_group("Visuals")
## Optional visual effect scene (e.g. fire particles) instantiated on the entity when applied.
@export var effect_scene: PackedScene

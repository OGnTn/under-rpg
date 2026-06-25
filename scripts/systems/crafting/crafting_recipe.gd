class_name CraftingRecipe extends Resource

@export var name: String = "Recipe"
@export var ingredients: Array[RecipeIngredient]
@export var results: Array[RecipeIngredient]

## The station required to craft this. "manual" means it can be crafted in the basic inventory.
@export var station: String = "manual"

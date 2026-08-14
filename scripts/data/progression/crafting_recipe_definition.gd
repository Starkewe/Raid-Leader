extends Resource
class_name CraftingRecipeDefinition

@export var recipe_id: String = ""
@export var display_name: String = ""
@export var source_encounter_id: String = ""
@export var output_weapon_id: String = ""
@export var ingredients: Array[CraftingIngredientDefinition] = []


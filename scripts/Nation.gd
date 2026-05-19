class_name Nation
extends RefCounted

var id: int
var nation_name: String
var color: Color
var capital_pos: Vector2i
var is_defeated: bool = false

var food: float = 50.0
var production: float = 30.0
var gold: float = 20.0
var population: int = 5
var armies: Array = []

var generals: int = 0
var ministers: int = 0
var general_stance: String = "attack"  # "attack" or "defend"

var armies_built: int = 0
var farms_built: int = 0
var mines_built: int = 0
var garrisons_built: int = 0
var camps_built: int = 0
var nations_eliminated: int = 0

const ARMY_COST_PROD: float = 20.0
const ARMY_COST_FOOD: float = 10.0
const MAX_GENERALS: int = 3
const MAX_MINISTERS: int = 3
const MAX_CAMPS: int = 3
const GENERAL_COST: float = 120.0
const MINISTER_COST: float = 100.0
const CAMP_COST_PROD: float = 60.0

func can_build_army() -> bool:
	return production >= ARMY_COST_PROD and food >= ARMY_COST_FOOD

func spend_for_army():
	production -= ARMY_COST_PROD
	food -= ARMY_COST_FOOD

func can_hire_general() -> bool:
	return generals < MAX_GENERALS and gold >= GENERAL_COST

func can_hire_minister() -> bool:
	return ministers < MAX_MINISTERS and gold >= MINISTER_COST

func minister_multiplier() -> float:
	return 1.0 + ministers * 0.35

extends RefCounted

const Rules = preload("res://data/campaign/hyperspace.json")

static func cruise_speed(hull: Dictionary) -> float:
	return float(Rules.data.cruise_speed) * hull.speed

static func distance_per_day(hull: Dictionary) -> float:
	return cruise_speed(hull) / float(Rules.data.days_per_second)

static func fuel_for_distance(hull: Dictionary, distance: float) -> float:
	return distance * float(Rules.data.fuel_per_unit) * hull.fuel

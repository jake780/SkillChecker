class_name SkillCheckResolver
extends RefCounted

enum Result { MISS, GOOD, PERFECT }

const PERFECT_WINDOW_DEGREES := 8.0
const GOOD_WINDOW_DEGREES := 24.0

static func resolve(spinner_degrees: float, target_degrees: float) -> Dictionary:
	var distance := angle_distance_degrees(spinner_degrees, target_degrees)
	if distance <= PERFECT_WINDOW_DEGREES:
		return {
			"result": Result.PERFECT,
			"label": "PERFECT",
			"distance": distance,
			"charge": 28.0,
			"speed_bonus": 0.35
		}
	if distance <= GOOD_WINDOW_DEGREES:
		return {
			"result": Result.GOOD,
			"label": "GOOD",
			"distance": distance,
			"charge": 14.0,
			"speed_bonus": 0.12
		}
	return {
		"result": Result.MISS,
		"label": "MISS",
		"distance": distance,
		"charge": -6.0,
		"speed_bonus": 0.0
	}

static func angle_distance_degrees(a: float, b: float) -> float:
	var diff := fmod(absf(a - b), 360.0)
	return minf(diff, 360.0 - diff)
